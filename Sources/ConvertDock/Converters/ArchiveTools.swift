import Foundation
import UniformTypeIdentifiers

enum ArchiveTools {
    static var all: [Tool] {
        [
            Tool(id: "archive.zip", title: "Compress to ZIP", subtitle: "All items in one archive",
                 symbol: "doc.zipper", category: .archive, inputs: [.item],
                 keywords: ["zip", "compresser", "archive", "envoyer"], combinesInputs: true) { inputs, ctx in
                if inputs.count == 1 {
                    let out = ctx.output(for: inputs[0], ext: "zip")
                    try Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", inputs[0].path, out.path])
                    return [out]
                }
                // Plusieurs éléments : on les rassemble dans un dossier temporaire.
                let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    .appendingPathComponent("Archive")
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: staging.deletingLastPathComponent()) }
                for url in inputs {
                    try FileManager.default.copyItem(at: url, to: staging.appendingPathComponent(url.lastPathComponent))
                }
                let out = OutputLocation.uniqueURL(in: OutputLocation.current.directory(for: inputs[0]), stem: "Archive", ext: "zip")
                try Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", staging.path, out.path])
                return [out]
            },
            archive(id: "archive.targz", title: "Compress to TAR.GZ", subtitle: "Standard on Linux and servers", ext: "tar.gz",
                    keywords: ["tar", "gz", "gzip", "tgz", "linux"]) { staging, out, _ in
                try Shell.run("/usr/bin/tar", ["-czf", out.path, "-C", staging.deletingLastPathComponent().path, staging.lastPathComponent])
            },
            archive(id: "archive.tarxz", title: "Compress to TAR.XZ", subtitle: "Maximum compression", ext: "tar.xz",
                    keywords: ["tar", "xz", "lzma", "linux", "compression maximale"]) { staging, out, _ in
                try Shell.run("/usr/bin/tar", ["-cJf", out.path, "-C", staging.deletingLastPathComponent().path, staging.lastPathComponent])
            },
            archive(id: "archive.tarbz2", title: "Compress to TAR.BZ2", subtitle: "Classic Unix format", ext: "tar.bz2",
                    keywords: ["tar", "bz2", "bzip2", "tbz", "linux"]) { staging, out, _ in
                try Shell.run("/usr/bin/tar", ["-cjf", out.path, "-C", staging.deletingLastPathComponent().path, staging.lastPathComponent])
            },
            archive(id: "archive.zip.password", title: "Compress to ZIP with password", subtitle: "Asks for a password, opens everywhere", ext: "zip",
                    keywords: ["zip", "mot de passe", "password", "chiffrer", "protéger", "sécuriser", "encrypt"],
                    symbol: "lock.doc", configure: { url in await TextPrompt.password(url) }) { staging, out, parameters in
                guard let password = parameters.text, !password.isEmpty else { throw ToolError.failed(L("No password entered.")) }
                // shortcut: chiffrement ZipCrypto (seul format que tout le monde sait ouvrir, mais faible) et mot de passe visible
                // dans la liste des processus le temps de l'exécution ; passer à AES (7-Zip) si un vrai secret doit être protégé.
                try Shell.run("/usr/bin/zip", ["-q", "-r", "-y", "-P", password, out.path, staging.lastPathComponent],
                              in: staging.deletingLastPathComponent())
            },
            archive(id: "archive.aar", title: "Compress to Apple Archive", subtitle: "Fast, native .aar format", ext: "aar",
                    keywords: ["aar", "apple archive", "lzfse"]) { staging, out, _ in
                // `aa` archive le contenu d'un dossier : un fichier seul est d'abord placé dans un dossier temporaire.
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: staging.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    try Shell.run("/usr/bin/aa", ["archive", "-d", staging.path, "-o", out.path])
                } else {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: folder) }
                    try FileManager.default.copyItem(at: staging, to: folder.appendingPathComponent(staging.lastPathComponent))
                    try Shell.run("/usr/bin/aa", ["archive", "-d", folder.path, "-o", out.path])
                }
            },
            archive(id: "archive.dmg", title: "Create a disk image (.dmg)", subtitle: "Compressed image to distribute files", ext: "dmg",
                    keywords: ["dmg", "image disque", "disk image", "hdiutil", "distribuer"]) { staging, out, _ in
                try Shell.run("/usr/bin/hdiutil", ["create", "-volname", staging.lastPathComponent, "-srcfolder", staging.path,
                                                   "-ov", "-format", "UDZO", "-quiet", out.path])
            },
            Tool(id: "archive.unzip", title: "Decompress", subtitle: "Extract the archive contents",
                 symbol: "arrow.up.bin", category: .archive, inputs: [.zip, .archive].compactMap { $0 },
                 inputExtensions: ["aar", "tgz", "xz", "bz2", "gz", "tar", "rar", "7z", "iso", "cab", "lzh", "lha", "cpio", "xar", "pkg",
                                   "tbz", "tbz2", "txz", "lzma", "z", "warc", "jar", "ipa", "apk", "epub", "dmg"],
                 keywords: ["unzip", "unrar", "rar", "7z", "7zip", "iso", "dmg", "cab", "décompresser", "extraire", "ouvrir"]) { inputs, ctx in
                try inputs.map { url in
                    let folder = try PDFTools.makeFolder(for: url, name: "")
                    if url.contentType?.conforms(to: .zip) == true {
                        try Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, folder.path])
                    } else if url.pathExtension.lowercased() == "aar" {
                        try Shell.run("/usr/bin/aa", ["extract", "-i", url.path, "-d", folder.path])
                    } else if url.pathExtension.lowercased() == "dmg" {
                        // Image disque : montée en lecture seule, invisible dans le Finder, puis copiée.
                        let mount = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                        try Shell.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen",
                                                           "-mountpoint", mount.path, url.path])
                        defer { _ = try? Shell.run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }
                        try Shell.run("/usr/bin/ditto", [mount.path, folder.path])
                    } else {
                        try Shell.run("/usr/bin/tar", ["-xf", url.path, "-C", folder.path])
                    }
                    return folder
                }
            },
        ]
    }

    /// Outil d'archivage générique : un seul élément est archivé tel quel, plusieurs sont regroupés dans un dossier « Archive ».
    private static func archive(id: String, title: String, subtitle: String, ext: String, keywords: [String],
                                symbol: String? = nil, configure: Tool.Configurator? = nil,
                                make: @escaping @Sendable (_ source: URL, _ output: URL, _ parameters: ToolParameters) throws -> Void) -> Tool {
        Tool(id: id, title: title, subtitle: subtitle, symbol: symbol ?? (ext == "dmg" ? "externaldrive" : "archivebox"),
             category: .archive, inputs: [.item], keywords: ["compresser", "archive"] + keywords, combinesInputs: true,
             configure: configure) { inputs, ctx in
            let fm = FileManager.default
            if inputs.count == 1 {
                let out = OutputLocation.uniqueURL(in: OutputLocation.current.directory(for: inputs[0]), stem: inputs[0].lastPathComponent, ext: ext)
                try make(inputs[0], out, ctx.parameters)
                return [out]
            }
            let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Archive")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging.deletingLastPathComponent()) }
            for url in inputs { try fm.copyItem(at: url, to: staging.appendingPathComponent(url.lastPathComponent)) }
            let out = OutputLocation.uniqueURL(in: OutputLocation.current.directory(for: inputs[0]), stem: "Archive", ext: ext)
            try make(staging, out, ctx.parameters)
            return [out]
        }
    }
}
