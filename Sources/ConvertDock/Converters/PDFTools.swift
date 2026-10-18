import AppKit
import PDFKit
import UniformTypeIdentifiers

enum PDFTools {
    static var all: [Tool] {
        [
            pagesToImages(id: "pdf.to.png", name: "PNG", type: .png, ext: "png"),
            pagesToImages(id: "pdf.to.jpg", name: "JPEG", type: .jpeg, ext: "jpg"),
            Tool(id: "pdf.to.txt", title: "Extraire le texte", subtitle: "PDF → .txt", symbol: "text.alignleft",
                 category: .pdf, inputs: [.pdf], keywords: ["texte", "txt", "extraire", "copier"]) { inputs, ctx in
                try inputs.map { url in
                    let document = try open(url)
                    let out = ctx.output(for: url, ext: "txt")
                    try (document.string ?? "").write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "pdf.to.rtf", title: "Convertir en RTF", subtitle: "Texte mis en forme, éditable", symbol: "doc.text",
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
            Tool(id: "pdf.merge", title: "Fusionner les PDF", subtitle: "Un seul document, dans l'ordre",
                 symbol: "doc.on.doc", category: .pdf, inputs: [.pdf],
                 keywords: ["fusionner", "merge", "combiner", "assembler", "joindre"], combinesInputs: true, minimumInputs: 2) { inputs, ctx in
                let merged = PDFDocument()
                for url in inputs {
                    let document = try open(url)
                    for i in 0..<document.pageCount {
                        if let page = document.page(at: i) { merged.insert(page, at: merged.pageCount) }
                    }
                }
                let out = ctx.output(for: inputs[0], ext: "pdf", suffix: "fusionné")
                guard merged.write(to: out) else { throw ToolError.failed("Échec de l'écriture du PDF.") }
                return [out]
            },
            Tool(id: "pdf.split", title: "Séparer les pages", subtitle: "Un PDF par page", symbol: "rectangle.split.3x1",
                 category: .pdf, inputs: [.pdf], keywords: ["séparer", "split", "découper", "pages", "extraire"]) { inputs, ctx in
                var outputs: [URL] = []
                for url in inputs {
                    let document = try open(url)
                    let folder = try makeFolder(for: url, name: "pages")
                    for i in 0..<document.pageCount {
                        guard let page = document.page(at: i) else { continue }
                        let single = PDFDocument()
                        single.insert(page, at: 0)
                        single.write(to: folder.appendingPathComponent("\(url.baseName) - page \(i + 1).pdf"))
                        ctx.progress(Double(i + 1) / Double(document.pageCount))
                    }
                    outputs.append(folder)
                }
                return outputs
            },
            Tool(id: "pdf.compress", title: "Compresser le PDF", subtitle: "Images optimisées pour l'écran",
                 symbol: "arrow.down.doc", category: .pdf, inputs: [.pdf],
                 keywords: ["compresser", "réduire", "poids", "optimiser", "compress"]) { inputs, ctx in
                try inputs.map { url in
                    let document = try open(url)
                    let out = ctx.output(for: url, ext: "pdf", suffix: "compressé")
                    guard document.write(to: out, withOptions: [.optimizeImagesForScreenOption: true, .saveImagesAsJPEGOption: true]) else {
                        throw ToolError.failed("Échec de la compression.")
                    }
                    return out
                }
            },
            Tool(id: "pdf.ocr", title: "Rendre le PDF cherchable (OCR)", subtitle: "Ajoute une couche de texte aux scans",
                 symbol: "doc.text.magnifyingglass", category: .intelligence, inputs: [.pdf],
                 keywords: ["ocr", "scan", "cherchable", "searchable", "texte", "reconnaissance"]) { inputs, ctx in
                try inputs.map { url in
                    let document = try open(url)
                    let out = ctx.output(for: url, ext: "pdf", suffix: "OCR")
                    guard document.write(to: out, withOptions: [.saveTextFromOCROption: true]) else {
                        throw ToolError.failed("Échec de l'OCR.")
                    }
                    return out
                }
            },
            Tool(id: "pdf.rotate", title: "Pivoter toutes les pages", subtitle: "90° sens horaire", symbol: "rotate.right",
                 category: .pdf, inputs: [.pdf], keywords: ["pivoter", "rotation", "tourner"]) { inputs, ctx in
                try inputs.map { url in
                    let document = try open(url)
                    for i in 0..<document.pageCount {
                        if let page = document.page(at: i) { page.rotation = (page.rotation + 90) % 360 }
                    }
                    let out = ctx.output(for: url, ext: "pdf", suffix: "pivoté")
                    guard document.write(to: out) else { throw ToolError.failed("Échec de l'écriture du PDF.") }
                    return out
                }
            },
        ]
    }

    private static func pagesToImages(id: String, name: String, type: UTType, ext: String) -> Tool {
        Tool(id: id, title: "Convertir en images \(name)", subtitle: "Chaque page en haute résolution",
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
        if document.isLocked { throw ToolError.failed("« \(url.lastPathComponent) » est protégé par un mot de passe.") }
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
