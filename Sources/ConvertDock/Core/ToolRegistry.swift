import Foundation

enum ToolRegistry {
    /// Tous les outils, regroupés dans l'ordre des catégories.
    static let all: [Tool] = {
        let tools = VisionTools.all + SpeechTools.all + ImageTools.all + TrimTools.all + VideoTools.all + VideoEditTools.all
            + AudioTools.all + DocumentTools.all + SubtitleTools.all + PDFTools.all + ModelTools.all + DataTools.all + ArchiveTools.all
        let order = ToolCategory.allCases
        return tools.enumerated().sorted { a, b in
            let ca = order.firstIndex(of: a.element.category)!, cb = order.firstIndex(of: b.element.category)!
            return ca == cb ? a.offset < b.offset : ca < cb
        }.map(\.element)
    }()

    static func compatible(with urls: [URL]) -> [Tool] {
        urls.isEmpty ? all : all.filter { $0.accepts(all: urls) }
    }
}
