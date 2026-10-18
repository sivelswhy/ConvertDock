import AppKit
@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers

/// Rend les outils de ConvertDock trouvables depuis Spotlight.
///
/// Chaque outil est indexé (titre, description, mots-clés dans les deux langues et formulations
/// « pdf en png », « wav vers mp3 »…). Choisir un résultat ouvre ConvertDock sur cet outil ;
/// « Rechercher dans l'app » reprend la requête Spotlight dans la barre de recherche.
@MainActor
enum SpotlightIndex {
    private static let domain = "tools"
    private static let versionKey = "spotlightIndexVersion"

    /// Réindexe quand l'app ou la langue change.
    static func refreshIfNeeded() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let version = "\(build)-\(Locale.current.identifier)-\(ToolRegistry.all.count)"
        guard UserDefaults.standard.string(forKey: versionKey) != version else { return }

        let items = ToolRegistry.all.map(item(for:))
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items) { error in
                guard error == nil else { return }
                Task { @MainActor in UserDefaults.standard.set(version, forKey: versionKey) }
            }
        }
    }

    private static func item(for tool: Tool) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = tool.displayTitle
        attributes.displayName = tool.displayTitle
        attributes.contentDescription = "\(tool.displaySubtitle) — ConvertDock"
        attributes.keywords = keywords(for: tool)
        attributes.thumbnailData = thumbnail(for: tool)
        return CSSearchableItem(uniqueIdentifier: "tool:\(tool.id)", domainIdentifier: domain, attributeSet: attributes)
    }

    /// Mots-clés : textes anglais et traduits, mots-clés de l'outil et formulations « source → cible ».
    private static func keywords(for tool: Tool) -> [String] {
        var words: [String] = [tool.title, tool.subtitle, tool.displayTitle, tool.displaySubtitle,
                               tool.category.rawValue, tool.category.displayName, "ConvertDock", "convert", "convertir"]
        words += tool.keywords
        let outputs = SmartSearch.outputFormats(tool)
        // Les outils génériques (archives, Base64…) acceptent tout : pas de formulations « x en y » pour eux.
        let generic = tool.inputs.contains(.item) || tool.inputs.contains(.data)
        let pseudoFormats: Set<String> = ["favicon", "prores", "base64", "sha256", "image", "video", "audio", "document"]
        let sources = generic ? [] : SmartSearch.searchableFormats.filter {
            !pseudoFormats.contains($0) && SmartSearch.accepts(tool, format: $0)
        }
        for target in outputs.prefix(2) {
            words += ["\(target)", "to \(target)", "en \(target)", "vers \(target)"]
            for source in sources.prefix(30) where source != target {
                words += ["\(source) to \(target)", "\(source) en \(target)", "\(source) vers \(target)", "\(source)2\(target)"]
            }
        }
        var seen = Set<String>()
        return words.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Vignette : le symbole de l'outil sur une pastille aux couleurs de sa catégorie.
    private static func thumbnail(for tool: Tool) -> Data? {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: 30, yRadius: 30)
            let tint = NSColor(tool.category.tint)
            NSGradient(colors: [tint, tint.blended(withFraction: 0.35, of: .black) ?? tint])?.draw(in: path, angle: -90)
            let config = NSImage.SymbolConfiguration(pointSize: 56, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let s = symbol.size
                symbol.draw(in: NSRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height))
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Titres des outils indexés qui correspondent à une requête (même moteur que Spotlight).
    static func query(_ text: String) async -> [String] {
        let escaped = text.replacingOccurrences(of: "\"", with: "")
        let query = CSSearchQuery(queryString: "(title == \"*\(escaped)*\"cd || keywords == \"*\(escaped)*\"cd)",
                                  queryContext: { let c = CSSearchQueryContext(); c.fetchAttributes = ["title"]; return c }())
        var titles: [String] = []
        do {
            for try await result in query.results { titles.append(result.item.attributeSet.title ?? "?") }
        } catch {
            titles.append("Error: \(error.localizedDescription)")
        }
        return titles
    }

    // MARK: Ouverture depuis Spotlight

    /// Traite un résultat Spotlight choisi par l'utilisateur. Renvoie `false` si l'activité n'est pas la nôtre.
    static func handle(_ activity: NSUserActivity) -> Bool {
        switch activity.activityType {
        case CSSearchableItemActionType:
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  identifier.hasPrefix("tool:"),
                  let tool = ToolRegistry.all.first(where: { $0.id == identifier.dropFirst(5) }) else { return false }
            MainWindowController.shared.show()
            AppModel.shared.searchQuery = tool.displayTitle
            DispatchQueue.main.async { AppModel.shared.chooseFilesAndRun(tool) }
            return true
        case CSQueryContinuationActionType:
            guard let query = activity.userInfo?[CSSearchQueryString] as? String else { return false }
            MainWindowController.shared.show()
            AppModel.shared.searchQuery = query
            return true
        default:
            return false
        }
    }
}
