import AppKit
import PDFKit
import UniformTypeIdentifiers

enum PDFTools {
    static var all: [Tool] {
        [
            pagesToImages(id: "pdf.to.png", name: "PNG", type: .png, ext: "png"),
            pagesToImages(id: "pdf.to.jpg", name: "JPEG", type: .jpeg, ext: "jpg"),
            Tool(id: "pdf.to.txt", title: "Extract text", subtitle: "PDF → .txt", symbol: "text.alignleft",
                 category: .pdf, inputs: [.pdf], keywords: ["texte", "txt", "extraire", "copier"]) { inputs, ctx in
                try inputs.map { url in
                    let document = try open(url)
                    let out = ctx.output(for: url, ext: "txt")
                    try (document.string ?? "").write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "pdf.to.rtf", title: "Convert to RTF", subtitle: "Formatted, editable text", symbol: "doc.text",
                 category: .pdf, inputs: [.pdf], keywords: ["rtf", "word", "éditable", "texte"]) { inputs, ctx in
                try inputs.map { url in
                    let text = attributedText(try open(url))
                    let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                    let out = ctx.output(for: url, ext: "rtf")
                    try data.write(to: out)
                    return out
                }
            },
            Tool(id: "pdf.merge", title: "Merge PDFs", subtitle: "One document, in order",
                 symbol: "doc.on.doc", category: .pdf, inputs: [.pdf],
                 keywords: ["fusionner", "merge", "combiner", "assembler", "joindre"], combinesInputs: true, minimumInputs: 2) { inputs, ctx in
                let merged = PDFDocument()
                for url in inputs {
                    let document = try open(url)
                    for i in 0..<document.pageCount {
                        if let page = document.page(at: i) { merged.insert(page, at: merged.pageCount) }
                    }
                }
                let out = ctx.output(for: inputs[0], ext: "pdf", suffix: L("merged"))
                guard merged.write(to: out) else { throw ToolError.failed(L("Failed to write the PDF.")) }
                return [out]
            },
            Tool(id: "pdf.split", title: "Split pages", subtitle: "One PDF per page", symbol: "rectangle.split.3x1",
                 category: .pdf, inputs: [.pdf], keywords: ["séparer", "split", "découper", "pages", "extraire"]) { inputs, ctx in
                var outputs: [URL] = []
                for url in inputs {
                    let document = try open(url)
                    let folder = try makeFolder(for: url, name: L("pages"))
                    for i in 0..<document.pageCount {
                        guard let page = document.page(at: i) else { continue }
                        let single = PDFDocument()
                        single.insert(page, at: 0)
                        single.write(to: folder.appendingPathComponent("\(url.baseName) - \(L("page")) \(i + 1).pdf"))
                        ctx.progress(Double(i + 1) / Double(document.pageCount))
                    }
                    outputs.append(folder)
                }
                return outputs
            },
            Tool(id: "pdf.compress", title: "Compress PDF", subtitle: "Images optimized for screen",
                 symbol: "arrow.down.doc", category: .pdf, inputs: [.pdf],
                 keywords: ["compresser", "réduire", "poids", "optimiser", "compress"]) { inputs, ctx in
                try inputs.map { url in
                    let document = try open(url)
                    let out = ctx.output(for: url, ext: "pdf", suffix: L("compressed"))
                    guard document.write(to: out, withOptions: [.optimizeImagesForScreenOption: true, .saveImagesAsJPEGOption: true]) else {
                        throw ToolError.failed(L("Compression failed."))
                    }
                    return out
                }
            },
            Tool(id: "pdf.ocr", title: "Make PDF searchable (OCR)", subtitle: "Adds a text layer to scans",
                 symbol: "doc.text.magnifyingglass", category: .intelligence, inputs: [.pdf],
                 keywords: ["ocr", "scan", "cherchable", "searchable", "texte", "reconnaissance"]) { inputs, ctx in
                try inputs.map { url in
                    let document = try open(url)
                    let out = ctx.output(for: url, ext: "pdf", suffix: "OCR")
                    guard document.write(to: out, withOptions: [.saveTextFromOCROption: true]) else {
                        throw ToolError.failed(L("OCR failed."))
                    }
                    return out
                }
            },
            Tool(id: "pdf.rotate", title: "Rotate all pages", subtitle: "90° clockwise", symbol: "rotate.right",
                 category: .pdf, inputs: [.pdf], keywords: ["pivoter", "rotation", "tourner"]) { inputs, ctx in
                try inputs.map { url in
                    let document = try open(url)
                    for i in 0..<document.pageCount {
                        if let page = document.page(at: i) { page.rotation = (page.rotation + 90) % 360 }
                    }
                    let out = ctx.output(for: url, ext: "pdf", suffix: L("rotated"))
                    guard document.write(to: out) else { throw ToolError.failed(L("Failed to write the PDF.")) }
                    return out
                }
            },
            Tool(id: "pdf.to.docx", title: "Convert to Word (DOCX)", subtitle: "Editable text, for Word and Pages", symbol: "doc.text",
                 category: .pdf, inputs: [.pdf], keywords: ["word", "docx", "office", "éditable", "modifier", "pages"]) { inputs, ctx in
                var outputs: [URL] = []
                for url in inputs {
                    let text = attributedText(try open(url))
                    let out = ctx.output(for: url, ext: "docx")
                    try await DocumentTools.write(text, to: out, ext: "docx")
                    outputs.append(out)
                }
                return outputs
            },
            Tool(id: "pdf.encrypt", title: "Protect with a password", subtitle: "Password required to open",
                 symbol: "lock.doc", category: .pdf, inputs: [.pdf],
                 keywords: ["mot de passe", "password", "protéger", "chiffrer", "verrouiller", "sécuriser", "encrypt"],
                 configure: { url in await TextPrompt.password(url) }) { inputs, ctx in
                guard let password = ctx.parameters.text, !password.isEmpty else { throw ToolError.failed(L("No password entered.")) }
                return try inputs.map { url in
                    let document = try open(url)
                    let out = ctx.output(for: url, ext: "pdf", suffix: L("protected"))
                    guard document.write(to: out, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password]) else {
                        throw ToolError.failed(L("Failed to write the PDF."))
                    }
                    return out
                }
            },
            Tool(id: "pdf.decrypt", title: "Remove the password", subtitle: "Unlocked copy, with the right password",
                 symbol: "lock.open", category: .pdf, inputs: [.pdf],
                 keywords: ["mot de passe", "password", "déverrouiller", "déchiffrer", "unlock", "decrypt"],
                 configure: { url in await TextPrompt.password(url) }) { inputs, ctx in
                try inputs.map { url in
                    guard let document = PDFDocument(url: url) else { throw ToolError.unreadable(url) }
                    if document.isLocked, !document.unlock(withPassword: ctx.parameters.text ?? "") {
                        throw ToolError.failed(L("Wrong password."))
                    }
                    // Les pages copiées dans un nouveau document perdent le chiffrement d'origine.
                    let copy = PDFDocument()
                    for i in 0..<document.pageCount {
                        if let page = document.page(at: i) { copy.insert(page, at: copy.pageCount) }
                    }
                    let out = ctx.output(for: url, ext: "pdf", suffix: L("unlocked"))
                    guard copy.write(to: out) else { throw ToolError.failed(L("Failed to write the PDF.")) }
                    return out
                }
            },
            Tool(id: "pdf.page.numbers", title: "Number the pages", subtitle: "“3 / 12” at the bottom of each page",
                 symbol: "number", category: .pdf, inputs: [.pdf],
                 keywords: ["numéros", "numéroter", "pagination", "page numbers", "bas de page"]) { inputs, ctx in
                try inputs.map { url in
                    let out = ctx.output(for: url, ext: "pdf", suffix: L("numbered"))
                    try stamp(url, to: out) { rect, index, count in
                        let text = NSAttributedString(string: "\(index + 1) / \(count)", attributes: [
                            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.darkGray,
                        ])
                        text.draw(at: CGPoint(x: rect.midX - text.size().width / 2, y: rect.minY + 20))
                    }
                    return out
                }
            },
            Tool(id: "pdf.watermark", title: "Add a watermark", subtitle: "Diagonal text on every page",
                 symbol: "signature", category: .pdf, inputs: [.pdf],
                 keywords: ["filigrane", "watermark", "confidentiel", "brouillon", "copie", "tampon"],
                 configure: { url in await TextPrompt.watermark(url) }) { inputs, ctx in
                let label = ctx.parameters.text ?? L("CONFIDENTIAL")
                return try inputs.map { url in
                    let out = ctx.output(for: url, ext: "pdf", suffix: L("watermarked"))
                    try stamp(url, to: out) { rect, _, _ in
                        let size = min(rect.width, rect.height) / CGFloat(max(4, label.count)) * 1.6
                        let text = NSAttributedString(string: label, attributes: [
                            .font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: NSColor.red.withAlphaComponent(0.22),
                        ])
                        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
                        ctx.saveGState()
                        ctx.translateBy(x: rect.midX, y: rect.midY)
                        ctx.rotate(by: atan2(rect.height, rect.width))
                        let textSize = text.size()
                        text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
                        ctx.restoreGState()
                    }
                    return out
                }
            },
            Tool(id: "pdf.reverse", title: "Reverse page order", subtitle: "Last page first",
                 symbol: "arrow.up.arrow.down", category: .pdf, inputs: [.pdf],
                 keywords: ["inverser", "ordre", "pages", "reverse", "scanner", "recto verso"]) { inputs, ctx in
                try inputs.map { url in
                    let document = try open(url)
                    let reversed = PDFDocument()
                    for i in stride(from: document.pageCount - 1, through: 0, by: -1) {
                        if let page = document.page(at: i) { reversed.insert(page, at: reversed.pageCount) }
                    }
                    let out = ctx.output(for: url, ext: "pdf", suffix: L("reversed"))
                    guard reversed.write(to: out) else { throw ToolError.failed(L("Failed to write the PDF.")) }
                    return out
                }
            },
        ]
    }

    /// Texte mis en forme de toutes les pages, séparées par un saut de page.
    static func attributedText(_ document: PDFDocument) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for i in 0..<document.pageCount {
            if let page = document.page(at: i)?.attributedString { text.append(page) }
            text.append(NSAttributedString(string: "\n\u{0C}"))
        }
        return text
    }

    /// Redessine chaque page puis dessine par-dessus (`draw` reçoit le rectangle de la page dans un contexte AppKit).
    /// shortcut: les liens et champs de formulaire ne sont pas recopiés ; passer par des PDFAnnotation si besoin.
    static func stamp(_ url: URL, to out: URL, draw: (CGRect, Int, Int) -> Void) throws {
        let document = try open(url)
        guard let pdf = CGContext(out as CFURL, mediaBox: nil, nil) else { throw ToolError.failed(L("Failed to create the PDF.")) }
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let size = page.rotation % 180 == 0 ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
            var box = CGRect(origin: .zero, size: size)
            pdf.beginPage(mediaBox: &box)
            page.draw(with: .cropBox, to: pdf)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: false)
            draw(box, i, document.pageCount)
            NSGraphicsContext.restoreGraphicsState()
            pdf.endPage()
        }
        pdf.closePDF()
    }

    private static func pagesToImages(id: String, name: String, type: UTType, ext: String) -> Tool {
        Tool(id: id, title: "Convert to \(name) images", subtitle: "Each page in high resolution",
             symbol: "photo.on.rectangle", category: .pdf, inputs: [.pdf],
             keywords: ["image", "pages", ext, "exporter"]) { inputs, ctx in
            var outputs: [URL] = []
            for url in inputs {
                let document = try open(url)
                let single = document.pageCount == 1
                let folder = single ? nil : try makeFolder(for: url, name: name)
                for i in 0..<document.pageCount {
                    guard let page = document.page(at: i), let image = render(page, scale: 2.5) else { continue }
                    let out = folder?.appendingPathComponent("page-\(i + 1).\(ext)") ?? ctx.output(for: url, ext: ext)
                    try ImageIOHelpers.write(image, to: out, type: type, quality: 0.9)
                    if single { outputs.append(out) }
                    ctx.progress(Double(i + 1) / Double(document.pageCount))
                }
                if let folder { outputs.append(folder) }
            }
            return outputs
        }
    }

    static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw ToolError.unreadable(url) }
        if document.isLocked { throw ToolError.failed(L("“%@” is password protected.", url.lastPathComponent)) }
        return document
    }

    static func makeFolder(for url: URL, name: String) throws -> URL {
        let folder = OutputLocation.uniqueURL(in: OutputLocation.current.directory(for: url), stem: name.isEmpty ? url.baseName : "\(url.baseName) \(name)", ext: "")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let size = rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = ImageIOHelpers.context(width: w, height: h) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }
}
