import QuickLookThumbnailing
import SwiftUI

/// Champ de recherche en capsule de verre.
struct GlassSearchField: View {
    @Binding var text: String
    var placeholder = "Rechercher une action…"
    var height: CGFloat = 40
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: height * 0.38, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: height * 0.38))
                .focused(focus)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, height * 0.4)
        .frame(height: height)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(.snappy(duration: 0.2), value: text.isEmpty)
    }
}

/// Pastille d'icône teintée selon la catégorie de l'outil.
struct ToolIcon: View {
    let tool: Tool
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: tool.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [tool.category.tint.opacity(0.95), tool.category.tint.opacity(0.65)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: size * 0.3)
            )
            .glassEffect(.clear, in: .rect(cornerRadius: size * 0.3))
    }
}

/// Filtres de catégories : une rangée de pastilles de verre qui fusionnent entre elles.
struct CategoryChips: View {
    let categories: [ToolCategory]
    @Binding var selection: ToolCategory?
    var compact = false
    @Namespace private var glass

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 6) {
                    chip(nil, label: "Tout", symbol: "square.grid.2x2")
                    ForEach(categories) { category in
                        chip(category, label: category.rawValue, symbol: category.symbol)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ category: ToolCategory?, label: String, symbol: String) -> some View {
        let selected = selection == category
        let tint = category?.tint ?? .accentColor
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selection = category }
        } label: {
            Label(label, systemImage: symbol)
                .font(.system(size: compact ? 11.5 : 12.5, weight: selected ? .semibold : .medium))
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 5 : 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(tint.opacity(0.85)).interactive() : .regular.interactive(), in: .capsule)
        .glassEffectID(category?.id ?? "all", in: glass)
    }
}

/// Explication de la recherche intelligente (ex. conversion indisponible).
struct SearchNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "lightbulb")
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular.tint(.yellow.opacity(0.18)), in: .rect(cornerRadius: 14))
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Icône Finder d'un fichier.
struct FileIcon: View {
    let url: URL
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Vignette Quick Look (aperçu réel du contenu), avec l'icône Finder en attendant.
struct ThumbnailView: View {
    let url: URL
    var size: CGFloat = 64
    @ViewState private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            } else {
                FileIcon(url: url, size: size)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: size, height: size),
                scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail
            )
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = rep.nsImage
            }
        }
    }
}

/// Indicateur de progression circulaire.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 4
    var tint: Color = .accentColor
    var indeterminate = false
    @ViewState private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: indeterminate ? 0.28 : max(0.02, progress))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(indeterminate ? (spin ? 270 : -90) : -90))
                .animation(indeterminate ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .smooth, value: spin)
                .animation(.smooth, value: progress)
        }
        .onAppear { spin = true }
    }
}

/// Ligne d'historique d'une tâche.
struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if case .succeeded(let urls) = job.state, let first = urls.first {
                    ThumbnailView(url: first, size: 34)
                        .id(job.revision)
                } else {
                    ToolIcon(tool: job.tool, size: 34)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(job.tool.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(job.state.isFailure ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .contentShape(.rect)
    }

    private var detail: String {
        switch job.state {
        case .configuring: "En attente de réglages…"
        case .running: job.inputs.count == 1 ? job.inputs[0].lastPathComponent : "\(job.inputs.count) fichiers"
        case .succeeded(let urls): urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) fichiers créés"
        case .failed(let message): message
        case .cancelled: "Annulé"
        }
    }

    @ViewBuilder private var trailing: some View {
        switch job.state {
        case .configuring, .running:
            HStack(spacing: 8) {
                ProgressRing(progress: job.progress, lineWidth: 3, tint: job.tool.category.tint, indeterminate: job.progress == 0)
                    .frame(width: 18, height: 18)
                Button { job.cancel() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("Annuler")
            }
        case .succeeded(let urls):
            HStack(spacing: 6) {
                if job.tool.isRetouchable {
                    Button { Task { await AppModel.shared.retouch(job) } } label: { Image(systemName: "wand.and.stars") }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .help("Retoucher le détourage")
                }
                if job.showsImagePreview {
                    Button { AppModel.shared.preview = job } label: { Image(systemName: "eye") }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .help("Voir le résultat")
                }
                if urls.count == 1 {
                    Button("Ouvrir") { NSWorkspace.shared.open(urls[0]) }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                Button { NSWorkspace.shared.activateFileViewerSelecting(urls) } label: { Image(systemName: "folder") }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("Afficher dans le Finder")
            }
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .cancelled:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }
}

extension Job.State {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

extension URL {
    var formattedSize: String {
        guard let size = try? resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

extension Array where Element == URL {
    /// Résumé lisible d'une sélection : « photo.png » ou « 3 fichiers ».
    var selectionTitle: String {
        count == 1 ? self[0].lastPathComponent : "\(count) fichiers"
    }
}

/// `@State` est une macro dans le SDK macOS 27, dont le plugin n'est fourni qu'avec Xcode.
/// L'alias permet d'utiliser directement le property wrapper et de compiler avec les seuls Command Line Tools.
typealias ViewState<Value> = SwiftUICore.State<Value>
