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
                    let document = try open(url)
                    let text = NSMutableAttributedString()
                    for i in 0..<document.pageCount {
                        if let page = document.page(at: i)?.attributedString { text.append(page) }
                        text.append(NSAttributedString(string: "\n\u{0C}"))
                    }
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
        ]
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
