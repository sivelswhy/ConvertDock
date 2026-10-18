import AppKit
import Observation

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

    @discardableResult
    func run(_ tool: Tool, on urls: [URL]) -> Job {
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

    func clearFinishedJobs() {
        jobs.removeAll { !$0.isActive }
    }
}

enum Preferences {
    static let playSound = "playSound"
    static let revealWhenDone = "revealWhenDone"
    static let closePanelWhenDone = "closePanelWhenDone"
}
