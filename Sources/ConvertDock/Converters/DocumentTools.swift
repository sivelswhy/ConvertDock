import AppKit
import UniformTypeIdentifiers

/// Conversions de documents texte via le système de texte Cocoa (RTF, DOCX, ODT, HTML, Markdown, PDF…).
enum DocumentTools {
    private static let readable: [UTType] = [.rtf, .rtfd, .html, .plainText, .docx, .doc, .odt, .webArchive, .markdown, .flatRTFD, .epub]
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
        Target(name: "Plain text (TXT)", ext: "txt", type: [.plainText], keywords: ["txt", "texte", "brut"]),
        Target(name: "Web Archive", ext: "webarchive", type: [.webArchive], keywords: ["webarchive", "safari", "archive web"]),
        Target(name: "RTFD", ext: "rtfd", type: [.rtfd], keywords: ["rtfd", "textedit", "images"]),
    ]

    static var all: [Tool] {
        var tools = targets.map { target in
            Tool(id: "doc.to.\(target.ext)", title: "Convert to \(target.name)", subtitle: "Document → .\(target.ext)",
                 symbol: target.ext == "pdf" ? "doc.richtext" : target.ext == "webarchive" ? "safari" : "doc.text", category: .document,
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
        tools.append(Tool(id: "doc.md.to.html", title: "Markdown → styled HTML", subtitle: "Web page ready to publish",
                          symbol: "chevron.left.forwardslash.chevron.right", category: .document, inputs: [.markdown],
                          keywords: ["markdown", "md", "html", "web"]) { inputs, ctx in
            try inputs.map { url in
                let text = try String(contentsOf: url, encoding: .utf8)
                let out = ctx.output(for: url, ext: "html", suffix: L("rendered"))
                try Markdown.html(from: text, title: url.baseName).write(to: out, atomically: true, encoding: .utf8)
                return out
            }
        })
        tools.append(Tool(id: "doc.code.to.pdf", title: "Code → PDF", subtitle: "Monospaced, ready to print",
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
        tools.append(Tool(id: "doc.stats", title: "Count words", subtitle: "Words, characters, reading time",
                          symbol: "number", category: .document, inputs: readable,
                          keywords: ["compter", "mots", "statistiques", "caractères", "word count"]) { inputs, ctx in
            var outputs: [URL] = []
            for url in inputs {
                let text = try await load(url).string
                let words = text.split { $0.isWhitespace || $0.isNewline }.count
                let report = [
                    url.lastPathComponent,
                    L("Words: %d", words),
                    L("Characters: %d", text.count),
                    L("Characters (no spaces): %d", text.filter { !$0.isWhitespace }.count),
                    L("Lines: %d", text.components(separatedBy: .newlines).count),
                    L("Estimated reading time: %d min", max(1, words / 230)),
                ].joined(separator: "\n")
                let out = ctx.output(for: url, ext: "txt", suffix: L("stats"))
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
        if url.pathExtension.lowercased() == "epub" {
            let (html, base) = try EPUB.html(url)
            return try NSAttributedString(data: Data(html.utf8), options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
                .baseURL: base,
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
        case "webarchive": type = .webArchive
        case "rtfd":
            guard let wrapper = text.rtfdFileWrapper(from: range, documentAttributes: [:]) else {
                throw ToolError.failed(L("Failed to write %@.", out.lastPathComponent))
            }
            try wrapper.write(to: out, options: .atomic, originalContentsURL: nil)
            return
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
            throw ToolError.failed(L("Failed to create the PDF."))
        }
    }
}

/// Livre EPUB : chapitres lus dans l'ordre de lecture (spine) et réunis en une seule page HTML.
enum EPUB {
    static func html(_ url: URL) throws -> (html: String, base: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("epub-" + UUID().uuidString)
        try Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, folder.path])
        // Le dossier est gardé jusqu'à la fin de la session : les images du livre y sont référencées.
        let container = try String(contentsOf: folder.appendingPathComponent("META-INF/container.xml"), encoding: .utf8)
        guard let opfPath = attribute("full-path", in: container) else { throw ToolError.unreadable(url) }
        let opfURL = folder.appendingPathComponent(opfPath)
        let opf = try String(contentsOf: opfURL, encoding: .utf8)
        var hrefs: [String: String] = [:]
        for item in tags("item", in: opf) {
            if let id = attribute("id", in: item), let href = attribute("href", in: item) { hrefs[id] = href }
        }
        let base = opfURL.deletingLastPathComponent()
        var body = ""
        for ref in tags("itemref", in: opf) {
            guard let id = attribute("idref", in: ref), let href = hrefs[id] else { continue }
            let chapter = base.appendingPathComponent(href.removingPercentEncoding ?? href)
            guard let text = try? String(contentsOf: chapter, encoding: .utf8) else { continue }
            let content = text.range(of: "(?s)<body[^>]*>(.*)</body>", options: .regularExpression)
                .map { String(text[$0]) } ?? text
            body += content.replacingOccurrences(of: "</?body[^>]*>", with: "", options: .regularExpression) + "\n"
        }
        guard !body.isEmpty else { throw ToolError.unreadable(url) }
        return ("<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>", base)
    }

    private static func tags(_ name: String, in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "<(?:\\w+:)?\(name)\\b[^>]*>")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let regex = try! NSRegularExpression(pattern: "\\s\(name)\\s*=\\s*[\"']([^\"']*)[\"']")
        guard let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range])
    }
}
