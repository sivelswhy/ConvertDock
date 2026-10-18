import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var model = AppModel.shared
    @ViewState private var query = ""
    @ViewState private var category: ToolCategory?
    @ViewState private var dropTargeted = false
    @ViewState private var showActivity = true
    @FocusState private var searchFocused: Bool

    private var available: [Tool] { ToolRegistry.compatible(with: model.files) }

    private var categories: [ToolCategory] {
        let present = Set(available.map(\.category))
        return ToolCategory.allCases.filter(present.contains)
    }

    private var results: [Tool] {
        available.filter { (category == nil || $0.category == category) && $0.matches(query) }
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 16) {
                topBar
                dropArea
                toolGrid
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            VStack {
                Spacer()
                if !model.jobs.isEmpty { activityTray }
            }
            .padding(16)

            if dropTargeted { dropOverlay }
        }
        .frame(minWidth: 760, minHeight: 560)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(from: providers) { urls in add(urls) }
            return true
        }
        .background {
            // Raccourcis clavier : ⌘F recherche, ⌘O ouvrir.
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
            Button("") { openFiles() }.keyboardShortcut("o").hidden()
        }
        .onChange(of: model.files) { if let category, !categories.contains(category) { self.category = nil } }
    }

    // MARK: Barre du haut

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                GlassSearchField(text: $query, placeholder: "Rechercher : svg, détourer, mp4, compresser…", height: 40, focus: $searchFocused)
                Button(action: openFiles) {
                    Label("Ouvrir", systemImage: "plus")
                        .frame(height: 26)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .help("Choisir des fichiers (⌘O)")
            }
            .padding(.leading, 70) // laisse la place aux boutons de fenêtre
            CategoryChips(categories: categories, selection: $category)
        }
    }

    // MARK: Zone de dépôt / fichiers sélectionnés

    @ViewBuilder private var dropArea: some View {
        if model.files.isEmpty {
            HStack(spacing: 16) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Déposez des fichiers ici")
                        .font(.system(size: 15, weight: .semibold))
                    Text("ou directement sur l'icône de ConvertDock dans le Dock ou sur le Bureau")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .padding(5)
            )
        } else {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.files, id: \.self) { url in
                            FileChip(url: url) { model.files.removeAll { $0 == url } }
                        }
                    }
                    .padding(4)
                }
                Text("\(results.count) actions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Button("Effacer") { withAnimation(.smooth) { model.files.removeAll() } }
                    .buttonStyle(.glass)
            }
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }

    // MARK: Grille des outils

    private var toolGrid: some View {
        ScrollView {
            if results.isEmpty {
                ContentUnavailableView(
                    available.isEmpty ? "Aucune action pour ces fichiers" : "Aucun résultat pour « \(query) »",
                    systemImage: "magnifyingglass",
                    description: Text(available.isEmpty ? "Ce type de fichier n'est pas encore pris en charge." : "Essayez « svg », « mp4 », « pdf »…")
                )
                .padding(.top, 80)
            }
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(ToolCategory.allCases) { category in
                    let tools = results.filter { $0.category == category }
                    if !tools.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(category.rawValue, systemImage: category.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                                ForEach(tools) { tool in
                                    ToolCard(tool: tool, ready: !model.files.isEmpty) { activate(tool) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, model.jobs.isEmpty ? 24 : 130)
            .padding(.horizontal, 2)
            .padding(.top, 2)
        }
        .scrollIndicators(.automatic)
        .scrollClipDisabled()
        .animation(.smooth(duration: 0.3), value: results.map(\.id))
    }

    // MARK: Activité

    private var activityTray: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Activité", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button("Effacer") { withAnimation { model.clearFinishedJobs() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.smooth) { showActivity.toggle() }
                } label: {
                    Image(systemName: showActivity ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if showActivity {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.jobs) { job in JobRow(job: job) }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: 170)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 620)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 26))
            .overlay {
                Label("Déposer pour convertir", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.4)), in: .capsule)
            }
            .padding(10)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    // MARK: Actions

    private func add(_ urls: [URL]) {
        withAnimation(.smooth) {
            for url in urls where !model.files.contains(url) { model.files.append(url) }
        }
    }

    private func activate(_ tool: Tool) {
        if model.files.isEmpty {
            // Pas encore de fichier : on en demande un, compatible avec l'outil.
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = tool.inputs.contains(.item)
            panel.allowedContentTypes = tool.inputs
            panel.message = tool.title
            guard panel.runModal() == .OK, tool.accepts(all: panel.urls) else { return }
            AppModel.shared.run(tool, on: panel.urls)
        } else {
            AppModel.shared.run(tool, on: model.files)
        }
        withAnimation(.smooth) { showActivity = true }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { add(panel.urls) }
    }
}

private struct ToolCard: View {
    let tool: Tool
    let ready: Bool
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ToolIcon(tool: tool, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(tool.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: ready ? "play.fill" : "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tool.category.tint)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .glassEffect(hovering ? .regular.tint(tool.category.tint.opacity(0.15)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 18))
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.snappy(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .help(ready ? "Lancer sur les fichiers sélectionnés" : "Choisir un fichier puis lancer")
    }
}

private struct FileChip: View {
    let url: URL
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailView(url: url, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(url.formattedSize)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 160, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// Fond doux et coloré pour que le verre ait quelque chose à réfracter.
struct AmbientBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / 8
            Canvas { ctx, size in
                let blobs: [(Color, Double, Double)] = [(.blue, 0, 0.9), (.purple, 2.1, 0.75), (.pink, 4.2, 0.6), (.teal, 1.3, 0.7)]
                for (color, phase, scale) in blobs {
                    let x = size.width * (0.5 + 0.38 * cos(t + phase))
                    let y = size.height * (0.5 + 0.36 * sin(t * 0.8 + phase * 1.3))
                    let r = max(size.width, size.height) * 0.42 * scale
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .radialGradient(Gradient(colors: [color.opacity(0.32), color.opacity(0)]),
                                                   center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Récupère les URL de fichiers d'un glisser-déposer.
func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for provider in providers {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        MainActor.assumeIsolated { completion(urls) }
    }
}
