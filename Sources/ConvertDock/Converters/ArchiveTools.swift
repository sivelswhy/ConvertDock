import Foundation
import UniformTypeIdentifiers

enum ArchiveTools {
    static var all: [Tool] {
        [
            Tool(id: "archive.zip", title: "Compresser en ZIP", subtitle: "Tous les éléments dans une archive",
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
            Tool(id: "archive.unzip", title: "Décompresser", subtitle: "Extraire le contenu de l'archive",
                 symbol: "arrow.up.bin", category: .archive, inputs: [.zip, .archive].compactMap { $0 },
                 keywords: ["unzip", "décompresser", "extraire", "ouvrir"]) { inputs, ctx in
                try inputs.map { url in
                    let folder = try PDFTools.makeFolder(for: url, name: "")
                    if url.contentType?.conforms(to: .zip) == true {
                        try Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, folder.path])
                    } else {
                        try Shell.run("/usr/bin/tar", ["-xf", url.path, "-C", folder.path])
                    }
                    return folder
                }
            },
        ]
    }
}
