import SwiftUI

/// Aperçu d'un résultat image, avec comparaison avant / après par curseur quand le cadrage est identique.
struct ResultPreview: View {
    let job: Job
    @ViewState private var before: NSImage?
    @ViewState private var after: NSImage?
    @ViewState private var split: CGFloat = 0.5

    private var loadKey: String { "\(job.outputs.first?.path ?? "")#\(job.revision)" }

    var body: some View {
        GeometryReader { geo in
            if let after {
                let fit = fitted(after.size, in: geo.size)
                let comparable = before.map { abs($0.size.width / $0.size.height - after.size.width / after.size.height) < 0.01 } ?? false

                ZStack(alignment: .topLeading) {
                    Checkerboard()
                    Image(nsImage: after)
                        .resizable()
                        .interpolation(.high)
                    if comparable, let before {
                        Image(nsImage: before)
                            .resizable()
                            .interpolation(.high)
                            .mask(alignment: .leading) { Rectangle().frame(width: fit.width * split) }
                        divider(fit)
                        badge("Avant").padding(10)
                        badge("Après").padding(10).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(width: fit.width, height: fit.height)
                .clipShape(.rect(cornerRadius: 14))
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        guard comparable else { return }
                        split = min(max(value.location.x / fit.width, 0), 1)
                    }
                )
                .position(x: fit.midX, y: fit.midY)
                .onTapGesture(count: 2) { if let url = job.outputs.first { NSWorkspace.shared.open(url) } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: loadKey) {
            guard let output = job.outputs.first else { return }
            after = NSImage(contentsOf: output)
            if before == nil, let input = job.inputs.first, input.contentType?.conforms(to: .image) == true {
                before = NSImage(contentsOf: input)
            }
        }
    }

    private func divider(_ fit: CGRect) -> some View {
        let x = fit.width * split
        return ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: fit.height)
                .shadow(color: .black.opacity(0.35), radius: 2)
            Image(systemName: "chevron.left.chevron.right")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 30, height: 30)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .frame(width: 30, height: fit.height)
        .offset(x: x - 15)
        .allowsHitTesting(false)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
            .allowsHitTesting(false)
    }

    private func fitted(_ size: CGSize, in box: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: box) }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }
}

/// Fiche de résultat affichée dans la fenêtre principale après une action produisant une image.
struct ResultSheet: View {
    let job: Job
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ToolIcon(tool: job.tool, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.tool.title).font(.system(size: 15, weight: .semibold))
                    if let url = job.outputs.first {
                        Text("\(url.lastPathComponent) · \(url.formattedSize)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .id(job.revision)
                    }
                }
                Spacer()
            }
            ResultPreview(job: job)
                .frame(minWidth: 620, minHeight: 440)
            ResultActions(job: job, onClose: { dismiss() })
        }
        .padding(22)
        .frame(width: 720, height: 620)
    }
}

/// Boutons sous un résultat : Retoucher (détourages), Finder, Ouvrir.
struct ResultActions: View {
    let job: Job
    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let onBack {
                    Button(action: onBack) { Label("Autre action", systemImage: "chevron.left") }
                        .buttonStyle(.glass)
                }
                if job.tool.isRetouchable {
                    Button {
                        Task { await AppModel.shared.retouch(job) }
                    } label: {
                        Label("Retoucher", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.glass)
                    .help("Pas satisfait ? Détourez vous-même avec la baguette magique et le pinceau")
                }
                Spacer(minLength: 0)
                Button { NSWorkspace.shared.activateFileViewerSelecting(job.outputs) } label: { Label("Finder", systemImage: "folder") }
                    .buttonStyle(.glass)
                if job.outputs.count == 1 {
                    Button {
                        NSWorkspace.shared.open(job.outputs[0])
                        onClose?()
                    } label: {
                        Label("Ouvrir", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.glass)
                }
                if let onClose {
                    Button("OK", action: onClose)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
    }
}
