import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Grandes familles d'outils, utilisées pour le filtrage et le regroupement.
enum ToolCategory: String, CaseIterable, Identifiable, Sendable {
    case intelligence = "AI"
    case image = "Images"
    case video = "Video"
    case audio = "Audio"
    case document = "Documents"
    case pdf = "PDF"
    case model = "3D"
    case data = "Data"
    case archive = "Archives"

    var id: String { rawValue }

    var displayName: String { L(rawValue) }

    var symbol: String {
        switch self {
        case .intelligence: "sparkles"
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .document: "doc.text"
        case .pdf: "doc.richtext"
        case .model: "cube"
        case .data: "curlybraces"
        case .archive: "archivebox"
        }
    }

    var tint: Color {
        switch self {
        case .intelligence: .purple
        case .image: .blue
        case .video: .pink
        case .audio: .orange
        case .document: .teal
        case .pdf: .red
        case .model: .indigo
        case .data: .green
        case .archive: .brown
        }
    }
}

/// Réglages choisis par l'utilisateur avant l'exécution (ex. plage de découpe).
struct ToolParameters: Sendable {
    /// Plage à conserver, en secondes.
    var trimStart: Double?
    var trimEnd: Double?
}

/// Contexte passé à un outil pendant son exécution.
struct JobContext: Sendable {
    var parameters = ToolParameters()
    let progress: @Sendable (Double) -> Void

    /// Emplacement de sortie pour un fichier source donné, sans collision de nom.
    func output(for input: URL, ext: String, suffix: String? = nil) -> URL {
        OutputLocation.url(for: input, ext: ext, suffix: suffix)
    }
}

/// Un outil de conversion ou de traitement.
struct Tool: Identifiable, Hashable, Sendable {
    typealias Runner = @Sendable (_ inputs: [URL], _ context: JobContext) async throws -> [URL]
    /// Interface affichée avant l'exécution, pour chaque fichier. `nil` en retour = annulé.
    typealias Configurator = @MainActor @Sendable (_ input: URL) async -> ToolParameters?

    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let category: ToolCategory
    /// Types acceptés en entrée (un fichier conforme à l'un d'eux est accepté).
    let inputs: [UTType]
    /// Extensions acceptées en plus des types (formats sans type système déclaré : srt, yaml, stl…).
    let inputExtensions: [String]
    /// Types exclus explicitement (ex. ne pas proposer « Convertir en PNG » pour un PNG).
    let excludes: [UTType]
    /// Exclusion stricte (type identique) plutôt que par conformité — ex. TXT exclut .txt mais pas .md.
    let exactExcludes: Bool
    let keywords: [String]
    /// Vrai si l'outil traite tous les fichiers ensemble (fusion PDF, archive…).
    let combinesInputs: Bool
    /// Nombre minimal de fichiers (2 pour une fusion).
    let minimumInputs: Int
    let configure: Configurator?
    let run: Runner

    init(
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        category: ToolCategory,
        inputs: [UTType],
        inputExtensions: [String] = [],
        excludes: [UTType] = [],
        exactExcludes: Bool = false,
        keywords: [String] = [],
        combinesInputs: Bool = false,
        minimumInputs: Int = 1,
        configure: Configurator? = nil,
        run: @escaping Runner
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.category = category
        self.inputs = inputs
        self.inputExtensions = inputExtensions
        self.excludes = excludes
        self.exactExcludes = exactExcludes
        self.keywords = keywords
        self.combinesInputs = combinesInputs
        self.minimumInputs = minimumInputs
        self.configure = configure
        self.run = run
    }

    static func == (lhs: Tool, rhs: Tool) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Détourages : le résultat peut être retouché à la main.
    var isRetouchable: Bool { id.hasPrefix("ai.removebg") }

    func accepts(_ url: URL) -> Bool {
        if inputExtensions.contains(url.pathExtension.lowercased()) { return true }
        guard let type = url.contentType else { return false }
        if excludes.contains(where: { exactExcludes ? type == $0 : type.conforms(to: $0) }) { return false }
        return inputs.contains(where: { type.conforms(to: $0) })
    }

    func accepts(all urls: [URL]) -> Bool {
        urls.count >= minimumInputs && urls.allSatisfy(accepts)
    }

    /// Recherche tolérante : insensible à la casse et aux accents, tous les mots doivent correspondre.
    var displayTitle: String { L(title) }
    var displaySubtitle: String { L(subtitle) }

    func matches(_ query: String) -> Bool {
        let terms = query.searchNormalized.split(separator: " ")
        guard !terms.isEmpty else { return true }
        // Recherche dans les deux langues : textes anglais d'origine, traductions et mots-clés.
        let haystack = ([title, subtitle, displayTitle, displaySubtitle, category.rawValue, category.displayName] + keywords)
            .joined(separator: " ")
            .searchNormalized
        return terms.allSatisfy { haystack.contains($0) }
    }
}

/// Chaîne traduite. Les textes sources sont en anglais ; les traductions sont dans
/// `Resources/<langue>.lproj/Localizable.strings` (actuellement le français).
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

/// Chaîne traduite avec arguments au format `String(format:)` (`%@`, `%d`…).
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: .current, arguments: arguments)
}

extension String {
    var searchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

extension URL {
    var contentType: UTType? {
        if let type = try? resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        return UTType(filenameExtension: pathExtension)
    }

    var baseName: String { deletingPathExtension().lastPathComponent }
}

enum ToolError: LocalizedError {
    case unreadable(URL)
    case unsupported(String)
    case failed(String)
    case noSubject(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): L("Could not read “%@”.", url.lastPathComponent)
        case .unsupported(let message): message
        case .failed(let message): message
        case .noSubject(let url): L("No subject detected in “%@”.", url.lastPathComponent)
        }
    }
}

/// Types personnalisés qui ne sont pas exposés par UTType.
extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    static let docx = UTType("org.openxmlformats.wordprocessingml.document") ?? .data
    static let doc = UTType("com.microsoft.word.doc") ?? .data
    static let odt = UTType("org.oasis-open.opendocument.text") ?? .data
    static let webArchive = UTType("com.apple.webarchive") ?? .data
    static let avif = UTType("public.avif") ?? .image
    static let csv = UTType.commaSeparatedText
    static let flac = UTType("org.xiph.flac") ?? .audio
}
