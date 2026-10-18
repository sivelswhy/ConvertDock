import Foundation

/// Où écrire les fichiers produits. Réglable dans les préférences.
enum OutputLocation: String, CaseIterable, Identifiable {
    case sameFolder
    case downloads
    case desktop

    static let defaultsKey = "outputLocation"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sameFolder: L("Next to the original file")
        case .downloads: L("Downloads folder")
        case .desktop: L("Desktop")
        }
    }

    static var current: OutputLocation {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(OutputLocation.init) ?? .sameFolder
    }

    func directory(for input: URL) -> URL {
        let fm = FileManager.default
        switch self {
        case .sameFolder:
            let folder = input.deletingLastPathComponent()
            return fm.isWritableFile(atPath: folder.path) ? folder : fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .downloads:
            return fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .desktop:
            return fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
    }

    /// Renvoie une URL libre : « photo.png », puis « photo 2.png », « photo 3.png »…
    static func url(for input: URL, ext: String, suffix: String? = nil) -> URL {
        let folder = current.directory(for: input)
        var stem = input.baseName
        if let suffix, !suffix.isEmpty { stem += " \(suffix)" }
        return uniqueURL(in: folder, stem: stem, ext: ext)
    }

    static func uniqueURL(in folder: URL, stem: String, ext: String) -> URL {
        let fm = FileManager.default
        func make(_ name: String) -> URL {
            ext.isEmpty ? folder.appendingPathComponent(name) : folder.appendingPathComponent(name).appendingPathExtension(ext)
        }
        var candidate = make(stem)
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = make("\(stem) \(index)")
            index += 1
        }
        return candidate
    }
}
