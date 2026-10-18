import AppKit
import Observation
import UniformTypeIdentifiers

/// Une exécution d'outil sur un ou plusieurs fichiers.
@MainActor
@Observable
final class Job: Identifiable {
    enum State: Equatable {
        case configuring
        case running
        case succeeded([URL])
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let tool: Tool
    let inputs: [URL]
    let startedAt = Date()
    var state: State = .running
    var progress: Double = 0
    /// Incrémenté quand un fichier de sortie est modifié (retouche), pour rafraîchir les aperçus.
    var revision = 0
    @ObservationIgnored var task: Task<Void, Never>?

    init(tool: Tool, inputs: [URL]) {
        self.tool = tool
        self.inputs = inputs
    }

    var isActive: Bool {
        switch state {
        case .configuring, .running: true
        default: false
        }
    }

    var outputs: [URL] {
        if case .succeeded(let urls) = state { return urls }
        return []
    }

    /// Un seul fichier image en sortie : on peut l'afficher en grand.
    var showsImagePreview: Bool {
        outputs.count == 1 && outputs[0].contentType?.conforms(to: .image) == true
    }

    func cancel() {
        task?.cancel()
        state = .cancelled
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// Fichiers déposés dans la fenêtre principale.
    var files: [URL] = []
    var jobs: [Job] = []
    /// Résultat affiché en grand dans la fenêtre principale.
    var preview: Job?
    /// Recherche de la fenêtre principale (aussi remplie depuis Spotlight).
    var searchQuery = ""

    /// Demande des fichiers compatibles avec l'outil, puis le lance (résultat affiché dans la fenêtre principale).
    func chooseFilesAndRun(_ tool: Tool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = tool.inputs.contains(.item)
        panel.allowedContentTypes = tool.inputs + tool.inputExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = tool.displayTitle
        NSApp.activate()
        guard panel.runModal() == .OK, tool.accepts(all: panel.urls) else { return }
        run(tool, on: panel.urls, presentResult: true)
    }

    @discardableResult
    func run(_ tool: Tool, on urls: [URL], presentResult: Bool = false) -> Job {
        let job = Job(tool: tool, inputs: urls)
        jobs.insert(job, at: 0)
        if jobs.count > 50 { jobs.removeLast(jobs.count - 50) }

        job.task = Task { @MainActor in
            let groups: [[URL]] = tool.combinesInputs ? [urls] : urls.map { [$0] }
            var outputs: [URL] = []
            do {
                for (index, group) in groups.enumerated() {
                    var parameters = ToolParameters()
                    if let configure = tool.configure {
                        job.state = .configuring
                        guard let chosen = await configure(group[0]) else {
                            job.state = .cancelled
                            return
                        }
                        parameters = chosen
                    }
                    job.state = .running
                    let total = Double(groups.count)
                    let context = JobContext(parameters: parameters) { p in
                        Task { @MainActor in job.progress = (Double(index) + min(max(p, 0), 1)) / total }
                    }
                    let result = try await Task.detached(priority: .userInitiated) {
                        try await tool.run(group, context)
                    }.value
                    try Task.checkCancellation()
                    outputs += result
                    job.progress = Double(index + 1) / total
                }
                job.state = .succeeded(outputs)
                finished(job)
                if presentResult && job.showsImagePreview { preview = job }
            } catch is CancellationError {
                job.state = .cancelled
            } catch {
                job.state = .failed(error.localizedDescription)
                NSSound(named: "Basso")?.play()
            }
        }
        return job
    }

    private func finished(_ job: Job) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Preferences.playSound) as? Bool ?? true {
            NSSound(named: "Glass")?.play()
        }
        if defaults.bool(forKey: Preferences.revealWhenDone) {
            NSWorkspace.shared.activateFileViewerSelecting(job.outputs)
        }
    }

    /// Rouvre le détourage dans l'éditeur manuel, pré-rempli avec le résultat, et remplace le fichier produit.
    func retouch(_ job: Job) async {
        guard job.tool.isRetouchable, let input = job.inputs.first, let output = job.outputs.first else { return }
        do {
            let original = try ImageIOHelpers.load(input, maxPixelSize: VisionTools.editorMaxSize)
            let current = try ImageIOHelpers.load(output)
            let sameFraming = abs(Double(current.width) / Double(current.height) - Double(original.width) / Double(original.height)) < 0.01
            let mask = sameFraming ? alphaMask(of: current, width: original.width, height: original.height) : try? VisionTools.subjectMask(original)
            guard var edited = await BackgroundEditor.present(input, image: original, initialMask: mask, message: nil) else { return }
            if job.tool.id == "ai.removebg.crop" { edited = VisionTools.cropToContent(edited) }
            try ImageIOHelpers.write(edited, to: output, type: .png)
            job.revision += 1
        } catch {
            job.state = .failed(error.localizedDescription)
        }
    }

    private func alphaMask(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard let ctx = ImageIOHelpers.context(width: width, height: height), let data = ctx.data else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let px = data.bindMemory(to: UInt8.self, capacity: height * ctx.bytesPerRow)
        var mask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { mask[y * width + x] = px[y * ctx.bytesPerRow + x * 4 + 3] }
        }
        return mask
    }

    func clearFinishedJobs() {
        jobs.removeAll { !$0.isActive }
    }
}

enum Preferences {
    static let playSound = "playSound"
    static let revealWhenDone = "revealWhenDone"
    static let closePanelWhenDone = "closePanelWhenDone"
}
