import AppKit
import SwiftUI

/// Masque de détourage éditable : baguette magique et pinceau sur une copie RGBA de l'image.
@MainActor
@Observable
final class MaskEditorModel {
    enum Mode: String, CaseIterable, Identifiable {
        case wand, erase, restore
        var id: String { rawValue }
        var label: String {
            switch self {
            case .wand: L("Magic wand")
            case .erase: L("Eraser")
            case .restore: L("Restore")
            }
        }
        var symbol: String {
            switch self {
            case .wand: "wand.and.stars"
            case .erase: "eraser"
            case .restore: "paintbrush.pointed"
            }
        }
    }

    let width: Int
    let height: Int
    /// Pixels RGBA non prémultipliés de l'image d'origine.
    private let pixels: [UInt8]
    /// Opacité par pixel (0 = arrière-plan supprimé).
    private(set) var mask: [UInt8]
    private var undoStack: [[UInt8]] = []

    var mode: Mode = .wand
    var tolerance: Double = 32
    var contiguous = true
    var brushSize: Double = 40
    var preview: CGImage?

    init(image: CGImage, initialMask: [UInt8]?) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        // Les pixels déjà transparents de l'original restent transparents.
        mask = initialMask ?? stride(from: 3, to: buffer.count, by: 4).map { buffer[$0] }
        pixels = buffer
        render()
    }

    var canUndo: Bool { !undoStack.isEmpty }

    func beginStroke() {
        undoStack.append(mask)
        if undoStack.count > 30 { undoStack.removeFirst() }
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        mask = last
        render()
    }

    func reset() {
        beginStroke()
        mask = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        render()
    }

    func invert() {
        beginStroke()
        mask = mask.map { 255 - $0 }
        render()
    }

    /// Baguette magique : supprime la zone de couleur proche du point cliqué.
    func wand(at x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        beginStroke()
        let seed = (y * width + x) * 4
        let sr = Int(pixels[seed]), sg = Int(pixels[seed + 1]), sb = Int(pixels[seed + 2])
        let limit = Int(tolerance * tolerance * 3)
        func similar(_ i: Int) -> Bool {
            let p = i * 4
            let dr = Int(pixels[p]) - sr, dg = Int(pixels[p + 1]) - sg, db = Int(pixels[p + 2]) - sb
            return dr * dr + dg * dg + db * db <= limit
        }
        if contiguous {
            var visited = [Bool](repeating: false, count: width * height)
            var stack = [y * width + x]
            visited[stack[0]] = true
            while let i = stack.popLast() {
                mask[i] = 0
                let px = i % width, py = i / width
                for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)] {
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let n = ny * width + nx
                    if !visited[n] && similar(n) {
                        visited[n] = true
                        stack.append(n)
                    }
                }
            }
        } else {
            for i in 0..<(width * height) where similar(i) { mask[i] = 0 }
        }
        render()
    }

    /// Pinceau (gomme ou restauration) avec bord adouci.
    func brush(at x: Double, _ y: Double) {
        let radius = brushSize / 2
        let restore = mode == .restore
        let x0 = max(0, Int(x - radius)), x1 = min(width - 1, Int(x + radius))
        let y0 = max(0, Int(y - radius)), y1 = min(height - 1, Int(y + radius))
        guard x0 <= x1, y0 <= y1 else { return }
        for py in y0...y1 {
            for px in x0...x1 {
                let d = ((Double(px) - x) * (Double(px) - x) + (Double(py) - y) * (Double(py) - y)).squareRoot()
                guard d <= radius else { continue }
                let strength = min(1, (radius - d) / max(1, radius * 0.25))
                let i = py * width + px
                let target: Double = restore ? Double(pixels[i * 4 + 3]) : 0
                let current = Double(mask[i])
                mask[i] = UInt8((current + (target - current) * strength).rounded())
            }
        }
        render()
    }

    func render() {
        preview = makeImage()
    }

    /// Image finale : couleurs d'origine, alpha = masque.
    func makeImage() -> CGImage? {
        var out = [UInt8](repeating: 0, count: pixels.count)
        for i in 0..<(width * height) {
            let a = Int(mask[i])
            guard a > 0 else { continue }
            let p = i * 4
            let srcA = Int(pixels[p + 3])
            // Les pixels source sont prémultipliés par leur alpha : on applique le masque relativement.
            let scale = srcA == 0 ? 0 : a * 255 / max(srcA, 1)
            let k = min(scale, 255)
            out[p] = UInt8(Int(pixels[p]) * k / 255)
            out[p + 1] = UInt8(Int(pixels[p + 1]) * k / 255)
            out[p + 2] = UInt8(Int(pixels[p + 2]) * k / 255)
            out[p + 3] = UInt8(min(a, srcA))
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Fenêtre de détourage manuel.
@MainActor
enum BackgroundEditor {
    private final class Delegate: NSObject, NSWindowDelegate {
        var onClose: () -> Void = {}
        func windowWillClose(_ notification: Notification) { onClose() }
    }

    /// Renvoie l'image détourée, ou `nil` si l'utilisateur annule.
    static func present(_ url: URL, image: CGImage, initialMask: [UInt8]?, message: String?) async -> CGImage? {
        let model = MaskEditorModel(image: image, initialMask: initialMask)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 780),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = L("Cut out “%@”", url.lastPathComponent)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 920, height: 560)
        window.level = .floating
        let delegate = Delegate()
        window.delegate = delegate

        let result: CGImage? = await withCheckedContinuation { continuation in
            var resumed = false
            func finish(_ image: CGImage?) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
            delegate.onClose = { finish(nil) }
            let view = MaskEditorView(model: model, message: message,
                                      onCancel: { finish(nil); window.close() },
                                      onDone: { finish(model.makeImage()); window.close() })
            let background = NSVisualEffectView()
            background.material = .underWindowBackground
            background.blendingMode = .behindWindow
            let hosting = NSHostingView(rootView: view)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: background.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            ])
            window.contentView = background
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        _ = delegate
        return result
    }
}

private struct MaskEditorView: View {
    @Bindable var model: MaskEditorModel
    let message: String?
    let onCancel: () -> Void
    let onDone: () -> Void
    @ViewState private var hover: CGPoint?
    @ViewState private var stroking = false

    var body: some View {
        VStack(spacing: 14) {
            if let message {
                Label(message, systemImage: "info.circle")
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .capsule)
            }
            canvas
            toolbar
        }
        .padding(.top, 36)
        .padding([.horizontal, .bottom], 18)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let fit = min(geo.size.width / CGFloat(model.width), geo.size.height / CGFloat(model.height))
            let size = CGSize(width: CGFloat(model.width) * fit, height: CGFloat(model.height) * fit)
            let origin = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)

            ZStack(alignment: .topLeading) {
                Checkerboard()
                    .frame(width: size.width, height: size.height)
                    .offset(x: origin.x, y: origin.y)
                if let preview = model.preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .offset(x: origin.x, y: origin.y)
                }
                if model.mode != .wand, let hover {
                    let d = model.brushSize * fit
                    Circle()
                        .strokeBorder(.white, lineWidth: 1.5)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .frame(width: d, height: d)
                        .offset(x: hover.x - d / 2, y: hover.y - d / 2)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(.rect)
            .onContinuousHover { phase in
                if case .active(let p) = phase { hover = p } else { hover = nil }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hover = value.location
                        let px = (value.location.x - origin.x) / fit
                        let py = (value.location.y - origin.y) / fit
                        if model.mode == .wand {
                            if !stroking { model.wand(at: Int(px), Int(py)) }
                        } else {
                            if !stroking { model.beginStroke() }
                            model.brush(at: px, py)
                        }
                        stroking = true
                    }
                    .onEnded { _ in stroking = false }
            )
        }
        .clipShape(.rect(cornerRadius: 18))
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            // Sélecteur segmenté natif : les trois modes restent bien distincts.
            Picker(L("Tool"), selection: $model.mode) {
                ForEach(MaskEditorModel.Mode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Divider().frame(height: 22)

            // Réglages du mode courant : libellés jamais tronqués, curseur de largeur fixe.
            HStack(spacing: 8) {
                if model.mode == .wand {
                    Text(L("Tolerance")).foregroundStyle(.secondary).fixedSize()
                    Slider(value: $model.tolerance, in: 4...120).frame(width: 130)
                    Toggle(L("Contiguous"), isOn: $model.contiguous)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                } else {
                    Text(L("Size")).foregroundStyle(.secondary).fixedSize()
                    Slider(value: $model.brushSize, in: 4...300).frame(width: 160)
                }
            }
            .font(.system(size: 12))
            .controlSize(.small)
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                    .keyboardShortcut("z")
                    .help(L("Undo (⌘Z)"))
                Button { model.invert() } label: { Image(systemName: "circle.lefthalf.filled.inverse") }
                    .help(L("Invert selection"))
                Button { model.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .help(L("Reset all"))
            }
            .buttonStyle(.glass)

            Button(L("Cancel"), action: onCancel)
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button(L("Save"), action: onDone)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Damier signalant la transparence.
struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 12
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.96)))
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                             with: .color(Color(white: 0.84)))
                }
            }
        }
    }
}
