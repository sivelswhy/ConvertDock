import SwiftUI

@MainActor
@Observable
final class QuickPanelModel {
    var urls: [URL] = []
    var query = ""
    var category: ToolCategory?
    var selectedID: String?
    var job: Job?
    var onClose: () -> Void = {}

    var compatible: [Tool] { ToolRegistry.compatible(with: urls) }

    var categories: [ToolCategory] {
        let present = Set(compatible.map(\.category))
        return ToolCategory.allCases.filter(present.contains)
    }

    var search: SmartSearch.Result {
        SmartSearch.search(compatible.filter { category == nil || $0.category == category }, query: query)
    }

    var results: [Tool] { search.tools }

    var sections: [(ToolCategory, [Tool])] {
        let results = results
        return ToolCategory.allCases.compactMap { category in
            let tools = results.filter { $0.category == category }
            return tools.isEmpty ? nil : (category, tools)
        }
    }

    func reset(with urls: [URL]) {
        self.urls = urls
        query = ""
        category = nil
        job = nil
        selectedID = results.first?.id
    }

    func ensureSelection() {
        if !results.contains(where: { $0.id == selectedID }) { selectedID = results.first?.id }
    }

    func move(_ delta: Int) {
        let list = sections.flatMap(\.1)
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selectedID } ?? -delta
        selectedID = list[(index + delta + list.count) % list.count].id
    }

    func runSelected() {
        guard let tool = results.first(where: { $0.id == selectedID }) else { return }
        run(tool)
    }

    func run(_ tool: Tool) {
        selectedID = tool.id
        job = AppModel.shared.run(tool, on: urls)
    }
}

struct QuickPanelView: View {
    @Bindable var model: QuickPanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let job = model.job {
                JobResultView(job: job, model: model)
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
            } else {
                picker
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: model.job?.id)
        .frame(width: 540, height: 600)
    }

    // MARK: Sélection d'action

    private var picker: some View {
        VStack(spacing: 14) {
            header
            GlassSearchField(text: $model.query, height: 42, focus: $searchFocused)
            if model.categories.count > 1 {
                CategoryChips(categories: model.categories, selection: $model.category, compact: true)
            }
            if let note = model.search.note {
                SearchNote(text: note)
            }
            list
        }
        .padding(.top, 18)
        .padding(.horizontal, 18)
        .onAppear { searchFocused = true }
        .onChange(of: model.query) { model.ensureSelection() }
        .onChange(of: model.category) { model.ensureSelection() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                ForEach(Array(model.urls.prefix(3).enumerated().reversed()), id: \.offset) { index, url in
                    ThumbnailView(url: url, size: 44)
                        .rotationEffect(.degrees(Double(index) * -7))
                        .offset(x: CGFloat(index) * -5)
                }
            }
            .frame(width: 52, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.urls.selectionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.urls.count == 1
                     ? [model.urls[0].contentType?.localizedDescription, model.urls[0].formattedSize].compactMap { $0 }.joined(separator: " · ")
                     : "\(model.compatible.count) actions disponibles")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .help("Fermer (Échap)")
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    if model.sections.isEmpty {
                        ContentUnavailableView(
                            model.compatible.isEmpty ? "Aucune action pour ce fichier" : "Aucun résultat",
                            systemImage: model.compatible.isEmpty ? "questionmark.folder" : "magnifyingglass",
                            description: Text(model.compatible.isEmpty ? "Ce type de fichier n'est pas encore pris en charge." : "Essayez un autre mot-clé.")
                        )
                        .padding(.top, 60)
                    }
                    ForEach(model.sections, id: \.0) { category, tools in
                        Text(category.rawValue.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                        ForEach(tools) { tool in
                            QuickToolRow(tool: tool, selected: tool.id == model.selectedID)
                                .id(tool.id)
                                .onTapGesture { model.run(tool) }
                                .onHover { if $0 { model.selectedID = tool.id } }
                        }
                    }
                }
                .padding(.bottom, 18)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.smooth(duration: 0.15)) { proxy.scrollTo(id) }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                     .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }
}

private struct QuickToolRow: View {
    let tool: Tool
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ToolIcon(tool: tool, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.title)
                    .font(.system(size: 13.5, weight: .medium))
                Text(tool.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if tool.configure != nil {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tool.category.tint.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tool.category.tint.opacity(0.35), lineWidth: 1))
            }
        }
        .contentShape(.rect)
        .animation(.snappy(duration: 0.12), value: selected)
    }
}

/// Progression puis résultat d'une action lancée depuis le panneau.
private struct JobResultView: View {
    let job: Job
    let model: QuickPanelModel

    var body: some View {
        if case .succeeded = job.state, job.showsImagePreview {
            imageResult
        } else {
            standardResult
        }
    }

    /// Résultat image : grand aperçu avant / après, et « Retoucher » pour les détourages.
    private var imageResult: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.tool.title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .id(job.revision)
                }
                Spacer()
                Button { model.onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
            }
            ResultPreview(job: job)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ResultActions(job: job, onBack: { model.job = nil })
        }
        .padding(20)
    }

    private var standardResult: some View {
        VStack(spacing: 20) {
            Spacer()
            status
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 30)
            Spacer()
            actions
        }
        .padding(24)
    }

    @ViewBuilder private var status: some View {
        switch job.state {
        case .configuring, .running:
            ZStack {
                ProgressRing(progress: job.progress, lineWidth: 6, tint: job.tool.category.tint, indeterminate: job.progress == 0)
                ToolIcon(tool: job.tool, size: 64)
            }
            .frame(width: 120, height: 120)
        case .succeeded(let urls):
            HStack(spacing: -24) {
                ForEach(Array(urls.prefix(3).enumerated()), id: \.offset) { index, url in
                    ThumbnailView(url: url, size: 120)
                        .rotationEffect(.degrees(urls.count > 1 ? Double(index - 1) * 6 : 0))
                }
            }
            .frame(height: 130)
            .onTapGesture(count: 2) { if let url = urls.first { NSWorkspace.shared.open(url) } }
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.orange)
                .frame(height: 120)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
                .frame(height: 120)
        }
    }

    private var title: String {
        switch job.state {
        case .configuring: "Réglez la découpe…"
        case .running: job.tool.title
        case .succeeded: "Terminé"
        case .failed: "Échec"
        case .cancelled: "Annulé"
        }
    }

    private var subtitle: String {
        switch job.state {
        case .configuring: "Déplacez les poignées jaunes puis cliquez sur « Couper »."
        case .running: job.progress > 0 ? "\(Int(job.progress * 100)) %" : "Traitement en cours…"
        case .succeeded(let urls): urls.count == 1 ? "\(urls[0].lastPathComponent) · \(urls[0].formattedSize)" : "\(urls.count) fichiers créés"
        case .failed(let message): message
        case .cancelled: "Aucun fichier n'a été créé."
        }
    }

    @ViewBuilder private var actions: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                switch job.state {
                case .configuring, .running:
                    Button("Annuler", role: .cancel) { job.cancel() }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                case .succeeded(let urls):
                    Button { model.job = nil } label: { Label("Autre action", systemImage: "chevron.left") }
                        .buttonStyle(.glass)
                    Button { NSWorkspace.shared.activateFileViewerSelecting(urls) } label: { Label("Finder", systemImage: "folder") }
                        .buttonStyle(.glass)
                    if urls.count == 1 {
                        Button { NSWorkspace.shared.open(urls[0]); model.onClose() } label: { Label("Ouvrir", systemImage: "arrow.up.forward.app") }
                            .buttonStyle(.glassProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                case .failed, .cancelled:
                    Button { model.job = nil } label: { Label("Retour", systemImage: "chevron.left") }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
    }
}
