import Foundation
import UniformTypeIdentifiers

/// Recherche « naturelle » : comprend « pdf to png », « wav vers mp3 », « heic en jpg », « mov → mp4 », « pdf2png »…
enum SmartSearch {
    struct Result {
        var tools: [Tool]
        /// Explication affichée quand la conversion demandée n'existe pas telle quelle.
        var note: String?
    }

    struct Intent: Equatable {
        var source: String?
        var target: String?
    }

    static func search(_ tools: [Tool], query: String) -> Result {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Result(tools: tools) }

        if let intent = parse(trimmed) {
            // Les conversions pures (« x.to.y ») d'abord, puis les autres outils compatibles.
            let direct = prioritized(tools.filter { matches($0, intent) })
            if !direct.isEmpty { return Result(tools: direct) }

            // Format de sortie indisponible : on propose son équivalent (MP3 → M4A, WebP → AVIF…).
            if let target = intent.target, let alternative = alternatives[target] {
                let alt = prioritized(tools.filter { matches($0, Intent(source: intent.source, target: alternative)) })
                if !alt.isEmpty {
                    let reason = unsupportedOutputs[target] ?? L("format unavailable")
                    return Result(tools: alt, note: L("No %@ output: %@. Here is the %@ equivalent.", target.uppercased(), reason, alternative.uppercased()))
                }
            }

            // Pas de conversion directe : on propose ce qui est possible depuis la source.
            if let source = intent.source, let target = intent.target {
                let fromSource = tools.filter { accepts($0, format: source) }
                let available = Set(fromSource.filter { $0.category != .data && $0.category != .archive }
                    .flatMap(outputFormats)).subtracting(families.keys).sorted()
                let reason = unsupportedOutputs[target].map { " (\($0))" } ?? ""
                let note = available.isEmpty
                    ? L("No conversion from %@ yet.", source.uppercased())
                    : L("No direct %@ → %@ conversion%@. Available outputs: %@.", source.uppercased(), target.uppercased(), reason,
                        available.map { $0.uppercased() }.joined(separator: ", "))
                return Result(tools: fromSource, note: note)
            }
            if let target = intent.target, let reason = unsupportedOutputs[target] {
                return Result(tools: tools.filter { $0.matches(strippingFillers(query)) },
                              note: L("No %@ output: %@.", target.uppercased(), reason))
            }
        }
        return Result(tools: tools.filter { $0.matches(strippingFillers(trimmed)) })
    }

    /// Les conversions pures (« x.to.y ») d'abord, puis les autres outils compatibles.
    private static func prioritized(_ tools: [Tool]) -> [Tool] {
        tools.enumerated()
            .sorted { ($0.element.id.contains(".to.") ? 0 : 1, $0.offset) < ($1.element.id.contains(".to.") ? 0 : 1, $1.offset) }
            .map(\.element)
    }

    // MARK: Analyse de la requête

    static func parse(_ query: String) -> Intent? {
        var q = " " + query.searchNormalized + " "
        for arrow in ["→", "->", "=>", ">", "»"] { q = q.replacingOccurrences(of: arrow, with: " to ") }
        // « pdf2png », « jpg2pdf »
        if let match = q.firstMatch(of: #/([a-z0-9]+)2([a-z][a-z0-9]*)/#),
           canonical(String(match.1)) != nil, canonical(String(match.2)) != nil {
            q = q.replacingOccurrences(of: String(match.0), with: "\(match.1) to \(match.2)")
        }
        let words = q.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)

        // « X to Y », « X vers Y », « X en Y », « X into Y »
        if let sepIndex = words.lastIndex(where: { separators.contains($0) }) {
            let left = words[..<sepIndex].compactMap(canonical)
            let right = words[(sepIndex + 1)...].compactMap(canonical)
            if let target = right.first {
                return Intent(source: left.last, target: target)
            }
        }
        // Deux formats côte à côte : « heic png »
        let formats = words.compactMap(canonical)
        if formats.count >= 2 { return Intent(source: formats[0], target: formats[1]) }
        return nil
    }

    private static let separators: Set<String> = ["to", "vers", "en", "into", "in", "a", "au", "pour"]

    private static let fillers: Set<String> = [
        "convertir", "convert", "conversion", "into", "a", "an", "the", "my", "file", "transformer", "changer", "un", "une", "le", "la", "les", "l", "des",
        "de", "du", "d", "fichier", "fichiers", "file", "files", "mon", "ma", "mes", "en", "to", "vers",
    ]

    private static func strippingFillers(_ query: String) -> String {
        let words = query.searchNormalized.split(separator: " ").filter { !fillers.contains(String($0)) }
        return words.isEmpty ? query : words.joined(separator: " ")
    }

    /// Nom de format canonique (extension), ou famille (« image », « video », « audio »…).
    static func canonical(_ word: String) -> String? {
        let w = word.searchNormalized.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?()\"'"))
        if let alias = aliases[w] { return alias }
        return knownFormats.contains(w) ? w : nil
    }

    private static let aliases: [String: String] = [
        "jpeg": "jpg", "jpe": "jpg", "tif": "tiff", "htm": "html", "markdown": "md", "texte": "txt", "text": "txt",
        "word": "docx", "photoshop": "psd", "quicktime": "mov", "aif": "aiff", "aac": "m4a", "alac": "m4a",
        "h264": "mp4", "h265": "hevc", "x265": "hevc", "heif": "heic", "mpeg4": "mp4", "excel": "csv", "tableur": "csv",
        "photo": "image", "photos": "image", "images": "image", "picture": "image", "img": "image",
        "videos": "video", "film": "video", "movie": "video", "son": "audio", "musique": "audio", "music": "audio",
        "sound": "audio", "pictures": "image", "videos ": "video", "icone": "icns", "icon": "icns", "favicon": "ico", "vecteur": "svg", "vector": "svg",
        "vectoriel": "svg", "archive": "zip", "plist": "plist", "propertylist": "plist", "gif anime": "gif",
        "documents": "document", "doc": "doc", "odf": "odt", "opendocument": "odt", "libreoffice": "odt",
    ]

    private static let families: [String: UTType] = [
        "image": .image, "video": .movie, "audio": .audio, "document": .text,
    ]

    private static let knownFormats: Set<String> = [
        "png", "jpg", "heic", "avif", "tiff", "gif", "bmp", "ico", "icns", "psd", "svg", "webp", "raw", "dng", "cr2", "nef",
        "pdf", "mp4", "mov", "m4v", "hevc", "mkv", "avi", "webm", "wmv", "mp3", "wav", "aiff", "caf", "flac", "m4a", "ogg",
        "opus", "wma", "docx", "doc", "odt", "rtf", "rtfd", "html", "txt", "md", "pages", "epub", "json", "csv", "tsv", "xml",
        "yaml", "yml", "zip", "tar", "gz", "tgz", "rar", "7z", "base64", "sha256",
        "image", "video", "audio", "document",
    ]

    private static let alternatives: [String: String] = [
        "mp3": "m4a", "ogg": "m4a", "opus": "m4a", "wma": "m4a", "webp": "avif",
        "mkv": "mp4", "avi": "mp4", "webm": "mp4", "wmv": "mp4", "rar": "zip", "7z": "zip", "pages": "docx",
    ]

    /// Formats que macOS ne sait pas produire nativement.
    private static var unsupportedOutputs: [String: String] {
        [
            "mp3": L("macOS cannot encode MP3 natively"),
            "webp": L("macOS cannot write WebP"),
            "ogg": L("format not supported by macOS"),
            "opus": L("format not supported by macOS"),
            "mkv": L("container not supported by macOS"),
            "avi": L("container not supported by macOS"),
            "webm": L("container not supported by macOS"),
            "wmv": L("Windows format not supported"),
            "wma": L("Windows format not supported"),
            "rar": L("proprietary format"),
            "7z": L("format not supported"),
            "epub": L("not supported yet"),
            "pages": L("Apple's proprietary format"),
        ]
    }

    // MARK: Correspondance avec les outils

    private static func matches(_ tool: Tool, _ intent: Intent) -> Bool {
        if let source = intent.source, !accepts(tool, format: source) { return false }
        if let target = intent.target, !produces(tool, format: target) { return false }
        // Évite « png → png » quand la source et la cible sont identiques et que l'outil n'est qu'une conversion.
        return true
    }

    static func accepts(_ tool: Tool, format: String) -> Bool {
        let type: UTType? = families[format] ?? (format == "hevc" ? .mpeg4Movie : UTType(filenameExtension: format))
        guard let type else { return false }
        if tool.excludes.contains(where: { tool.exactExcludes ? type == $0 : type.conforms(to: $0) }) { return false }
        return tool.inputs.contains { type.conforms(to: $0) }
    }

    private static func produces(_ tool: Tool, format: String) -> Bool {
        let outputs = outputFormats(tool)
        if let family = families[format] {
            return outputs.contains { UTType(filenameExtension: $0)?.conforms(to: family) == true }
        }
        return outputs.contains(format)
    }

    /// Formats produits par un outil, déduits de son identifiant (« image.to.png ») ou d'une table.
    static func outputFormats(_ tool: Tool) -> [String] {
        if let explicit = explicitOutputs[tool.id] { return explicit }
        if let range = tool.id.range(of: ".to.") {
            let ext = String(tool.id[range.upperBound...])
            return [aliases[ext] ?? ext]
        }
        return []
    }

    private static let explicitOutputs: [String: [String]] = [
        "ai.removebg": ["png"], "ai.removebg.crop": ["png"], "ai.removebg.manual": ["png"],
        "ai.vectorize.color": ["svg"], "ai.vectorize.mono": ["svg"], "ai.ocr": ["txt"],
        "ai.blurfaces": [], "ai.upscale": [], "pdf.ocr": ["pdf"],
        "image.merge.pdf": ["pdf"], "image.merge.gif": ["gif"], "image.gif.frames": ["png"], "image.thumb": ["png"],
        "image.compress": ["jpg"],
        "video.to.hevc": ["hevc", "mp4"], "video.1080": ["mp4"], "video.720": ["mp4"], "video.480": ["mp4"],
        "video.audio": ["m4a", "audio"], "video.poster": ["png"], "video.trim": ["mov", "mp4"],
        "audio.to.alac": ["m4a"], "audio.trim": ["m4a", "wav", "aiff", "flac"],
        "doc.md.to.html": ["html"], "doc.code.to.pdf": ["pdf"], "doc.stats": ["txt"],
        "pdf.to.png": ["png"], "pdf.to.jpg": ["jpg"], "pdf.merge": ["pdf"], "pdf.split": ["pdf"], "pdf.compress": ["pdf"],
        "pdf.rotate": ["pdf"],
        "data.json.to.plist": ["plist"], "data.plist.to.json": ["json"], "data.csv.to.json": ["json"],
        "data.json.to.csv": ["csv"], "data.json.pretty": ["json"], "data.json.minify": ["json"],
        "data.base64": ["base64", "txt"], "data.checksum": ["sha256"],
        "archive.zip": ["zip"], "archive.unzip": [],
    ]
}
