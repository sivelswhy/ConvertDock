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
                    keywords: ["tar", "gz", "gzip", "tgz", "linux"]) { staging, out in
                try Shell.run("/usr/bin/tar", ["-czf", out.path, "-C", staging.deletingLastPathComponent().path, staging.lastPathComponent])
            },
            archive(id: "archive.tarxz", title: "Compress to TAR.XZ", subtitle: "Maximum compression", ext: "tar.xz",
                    keywords: ["tar", "xz", "lzma", "linux", "compression maximale"]) { staging, out in
                try Shell.run("/usr/bin/tar", ["-cJf", out.path, "-C", staging.deletingLastPathComponent().path, staging.lastPathComponent])
            },
            archive(id: "archive.aar", title: "Compress to Apple Archive", subtitle: "Fast, native .aar format", ext: "aar",
                    keywords: ["aar", "apple archive", "lzfse"]) { staging, out in
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
                    keywords: ["dmg", "image disque", "disk image", "hdiutil", "distribuer"]) { staging, out in
                try Shell.run("/usr/bin/hdiutil", ["create", "-volname", staging.lastPathComponent, "-srcfolder", staging.path,
                                                   "-ov", "-format", "UDZO", "-quiet", out.path])
            },
            Tool(id: "archive.unzip", title: "Decompress", subtitle: "Extract the archive contents",
                 symbol: "arrow.up.bin", category: .archive, inputs: [.zip, .archive].compactMap { $0 },
                 inputExtensions: ["aar", "tgz", "xz", "bz2", "gz", "tar"],
                 keywords: ["unzip", "décompresser", "extraire", "ouvrir"]) { inputs, ctx in
                try inputs.map { url in
                    let folder = try PDFTools.makeFolder(for: url, name: "")
                    if url.contentType?.conforms(to: .zip) == true {
                        try Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, folder.path])
                    } else if url.pathExtension.lowercased() == "aar" {
                        try Shell.run("/usr/bin/aa", ["extract", "-i", url.path, "-d", folder.path])
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
                                make: @escaping @Sendable (_ source: URL, _ output: URL) throws -> Void) -> Tool {
        Tool(id: id, title: title, subtitle: subtitle, symbol: ext == "dmg" ? "externaldrive" : "archivebox",
             category: .archive, inputs: [.item], keywords: ["compresser", "archive"] + keywords, combinesInputs: true) { inputs, ctx in
            let fm = FileManager.default
            if inputs.count == 1 {
                let out = OutputLocation.uniqueURL(in: OutputLocation.current.directory(for: inputs[0]), stem: inputs[0].lastPathComponent, ext: ext)
                try make(inputs[0], out)
                return [out]
            }
            let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Archive")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging.deletingLastPathComponent()) }
            for url in inputs { try fm.copyItem(at: url, to: staging.appendingPathComponent(url.lastPathComponent)) }
            let out = OutputLocation.uniqueURL(in: OutputLocation.current.directory(for: inputs[0]), stem: "Archive", ext: ext)
            try make(staging, out)
            return [out]
        }
    }
}
