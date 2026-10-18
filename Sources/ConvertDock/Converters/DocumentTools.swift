import AppKit
import UniformTypeIdentifiers

/// Conversions de documents texte via le système de texte Cocoa (RTF, DOCX, ODT, HTML, Markdown, PDF…).
enum DocumentTools {
    private static let readable: [UTType] = [.rtf, .rtfd, .html, .plainText, .docx, .doc, .odt, .webArchive, .markdown, .flatRTFD]
    private static let sourceCode: [UTType] = [.sourceCode, .json, .xml, .propertyList, .commaSeparatedText, .yaml]

    private struct Target {
        let name: String
        let ext: String
        let type: [UTType]
        let keywords: [String]
    }

    private static let targets: [Target] = [
        Target(name: "PDF", ext: "pdf", type: [.pdf], keywords: ["pdf", "imprimer"]),
        Target(name: "Word (DOCX)", ext: "docx", type: [.docx], keywords: ["word", "docx", "office", "microsoft"]),
        Target(name: "Word 97 (DOC)", ext: "doc", type: [.doc], keywords: ["word", "doc", "ancien"]),
        Target(name: "OpenDocument (ODT)", ext: "odt", type: [.odt], keywords: ["odt", "libreoffice", "openoffice"]),
        Target(name: "RTF", ext: "rtf", type: [.rtf], keywords: ["rtf", "texte enrichi", "textedit"]),
        Target(name: "HTML", ext: "html", type: [.html], keywords: ["html", "web", "page"]),
        Target(name: "Texte brut (TXT)", ext: "txt", type: [.plainText], keywords: ["txt", "texte", "brut"]),
    ]

    static var all: [Tool] {
        var tools = targets.map { target in
            Tool(id: "doc.to.\(target.ext)", title: "Convertir en \(target.name)", subtitle: "Document → .\(target.ext)",
                 symbol: target.ext == "pdf" ? "doc.richtext" : "doc.text", category: .document,
                 inputs: readable, excludes: target.type, exactExcludes: target.ext == "txt",
                 keywords: ["convertir", "document"] + target.keywords) { inputs, ctx in
                var outputs: [URL] = []
                for url in inputs {
                    let out = ctx.output(for: url, ext: target.ext)
                    try await write(try await load(url), to: out, ext: target.ext)
                    outputs.append(out)
                }
                return outputs
            }
        }
        // Les fichiers « texte » (Markdown, code…) sont aussi des plainText : on garde la conversion TXT pour eux.
        tools.append(Tool(id: "doc.md.to.html", title: "Markdown → HTML stylé", subtitle: "Page web prête à publier",
                          symbol: "chevron.left.forwardslash.chevron.right", category: .document, inputs: [.markdown],
                          keywords: ["markdown", "md", "html", "web"]) { inputs, ctx in
            try inputs.map { url in
                let text = try String(contentsOf: url, encoding: .utf8)
                let out = ctx.output(for: url, ext: "html", suffix: "rendu")
                try Markdown.html(from: text, title: url.baseName).write(to: out, atomically: true, encoding: .utf8)
                return out
            }
        })
        tools.append(Tool(id: "doc.code.to.pdf", title: "Code → PDF", subtitle: "Police à chasse fixe, prêt à imprimer",
                          symbol: "curlybraces.square", category: .document, inputs: sourceCode,
                          keywords: ["code", "source", "pdf", "imprimer"]) { inputs, ctx in
            var outputs: [URL] = []
            for url in inputs {
                let text = try String(contentsOf: url, encoding: .utf8)
                let attributed = NSAttributedString(string: text, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
                    .foregroundColor: NSColor.black,
                ])
                let out = ctx.output(for: url, ext: "pdf")
                try await writePDF(attributed, to: out)
                outputs.append(out)
            }
            return outputs
        })
        tools.append(Tool(id: "doc.stats", title: "Compter les mots", subtitle: "Mots, caractères, temps de lecture",
                          symbol: "number", category: .document, inputs: readable,
                          keywords: ["compter", "mots", "statistiques", "caractères", "word count"]) { inputs, ctx in
            var outputs: [URL] = []
            for url in inputs {
                let text = try await load(url).string
                let words = text.split { $0.isWhitespace || $0.isNewline }.count
                let report = """
                \(url.lastPathComponent)
                Mots : \(words)
                Caractères : \(text.count)
                Caractères (sans espaces) : \(text.filter { !$0.isWhitespace }.count)
                Lignes : \(text.components(separatedBy: .newlines).count)
                Temps de lecture estimé : \(max(1, words / 230)) min
                """
                let out = ctx.output(for: url, ext: "txt", suffix: "statistiques")
                try report.write(to: out, atomically: true, encoding: .utf8)
                outputs.append(out)
            }
            return outputs
        })
        return tools
    }

    /// Chargement sur le thread principal : l'import HTML/DOCX de Cocoa l'exige.
    @MainActor
    static func load(_ url: URL) throws -> NSAttributedString {
        if url.contentType?.conforms(to: .markdown) == true || ["md", "markdown"].contains(url.pathExtension.lowercased()) {
            let text = try String(contentsOf: url, encoding: .utf8)
            let html = Markdown.html(from: text, title: url.baseName)
            return try NSAttributedString(data: Data(html.utf8), options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ], documentAttributes: nil)
        }
        return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
    }

    @MainActor
    static func write(_ text: NSAttributedString, to out: URL, ext: String) throws {
        let range = NSRange(location: 0, length: text.length)
        let type: NSAttributedString.DocumentType
        switch ext {
        case "pdf": return try writePDF(text, to: out)
        case "docx": type = .officeOpenXML
        case "doc": type = .docFormat
        case "odt": type = .openDocument
        case "rtf": type = .rtf
        case "html": type = .html
        default:
            try text.string.write(to: out, atomically: true, encoding: .utf8)
            return
        }
        let data = try text.data(from: range, documentAttributes: [
            .documentType: type,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ])
        try data.write(to: out)
    }

    /// Mise en page A4 paginée via le système d'impression, sans afficher de panneau.
    @MainActor
    static func writePDF(_ text: NSAttributedString, to out: URL) throws {
        let paper = NSSize(width: 595, height: 842)
        let margin: CGFloat = 56
        let info = NSPrintInfo()
        info.paperSize = paper
        info.topMargin = margin; info.bottomMargin = margin
        info.leftMargin = margin; info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = out

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: paper.width - margin * 2, height: paper.height - margin * 2))
        textView.appearance = NSAppearance(named: .aqua)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(text)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.sizeToFit()

        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: out.path) else {
            throw ToolError.failed("Échec de la création du PDF.")
        }
    }
}
