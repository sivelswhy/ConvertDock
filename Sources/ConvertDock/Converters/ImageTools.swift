import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit
import UniformTypeIdentifiers

enum ImageTools {
    private static let raster: [UTType] = [.image]
    /// Images dont ImageIO/NSImage savent produire un bitmap.
    private static let svg = UTType.svg

    static var all: [Tool] {
        conversions + transforms + combined
    }

    // MARK: Conversions de format

    private struct Target {
        let type: UTType
        let ext: String
        let name: String
        var quality: Double? = nil
        var maxSide: Int? = nil
        var keywords: [String] = []
    }

    private static let targets: [Target] = [
        Target(type: .png, ext: "png", name: "PNG", keywords: ["transparent", "sans perte"]),
        Target(type: .jpeg, ext: "jpg", name: "JPEG", quality: 0.9, keywords: ["jpg", "photo"]),
        Target(type: .heic, ext: "heic", name: "HEIC", quality: 0.85, keywords: ["heif", "iphone"]),
        Target(type: .avif, ext: "avif", name: "AVIF", quality: 0.8, keywords: ["web", "moderne"]),
        Target(type: .webP, ext: "webp", name: "WebP", quality: 0.82, keywords: ["web", "google", "site", "léger"]),
        Target(type: .tiff, ext: "tiff", name: "TIFF", keywords: ["tif", "impression"]),
        Target(type: .gif, ext: "gif", name: "GIF"),
        Target(type: .bmp, ext: "bmp", name: "BMP", keywords: ["bitmap", "windows"]),
        Target(type: .ico, ext: "ico", name: "ICO", maxSide: 256, keywords: ["favicon", "icône", "windows"]),
        Target(type: UTType("com.adobe.photoshop-image") ?? .image, ext: "psd", name: "PSD", keywords: ["photoshop"]),
        Target(type: UTType("public.jpeg-2000") ?? .image, ext: "jp2", name: "JPEG 2000", quality: 0.85, keywords: ["jpeg2000", "j2k", "cinéma"]),
        Target(type: UTType("com.ilm.openexr-image") ?? .image, ext: "exr", name: "OpenEXR", keywords: ["hdr", "vfx", "compositing", "blender"]),
        Target(type: UTType("com.truevision.tga-image") ?? .image, ext: "tga", name: "TGA", keywords: ["targa", "jeux", "game", "texture"]),
        Target(type: UTType("org.khronos.ktx") ?? .image, ext: "ktx", name: "KTX", keywords: ["texture", "gpu", "opengl", "jeux", "game"]),
        Target(type: UTType("com.microsoft.dds") ?? .image, ext: "dds", name: "DDS", keywords: ["texture", "directx", "jeux", "game"]),
    ]

    private static var conversions: [Tool] {
        var tools = targets.map { target in
            Tool(
                id: "image.to.\(target.ext)",
                title: "Convert to \(target.name)",
                subtitle: "Image → .\(target.ext)",
                symbol: "photo.on.rectangle.angled",
                category: .image,
                inputs: [.image, svg],
                excludes: [target.type],
                keywords: ["convertir", "format", target.ext] + target.keywords
            ) { inputs, ctx in
                try inputs.map { url in
                    var image = try ImageIOHelpers.load(url)
                    if let maxSide = target.maxSide {
                        image = ImageIOHelpers.resize(image, maxSide: maxSide, square: target.type == .ico)
                    }
                    let out = ctx.output(for: url, ext: target.ext)
                    try ImageIOHelpers.write(image, to: out, type: target.type, quality: target.quality)
                    return out
                }
            }
        }

        tools.append(Tool(
            id: "image.to.icns",
            title: "Create a macOS icon (.icns)",
            subtitle: "Every size from 16 to 1024 px",
            symbol: "app.badge",
            category: .image,
            inputs: [.image, svg],
            excludes: [.icns],
            keywords: ["icns", "icône", "app", "iconset"]
        ) { inputs, ctx in
            try inputs.map { url in
                let image = try ImageIOHelpers.load(url)
                let sizes = [16, 32, 64, 128, 256, 512, 1024]
                let frames = sizes.map { ImageIOHelpers.resize(image, maxSide: $0, square: true) }
                let out = ctx.output(for: url, ext: "icns")
                try ImageIOHelpers.writeMulti(frames, to: out, type: .icns)
                return out
            }
        })

        tools.append(Tool(
            id: "image.to.webp.lossless",
            title: "Convert to WebP (lossless)",
            subtitle: "Pixel-perfect, smaller than PNG",
            symbol: "photo.on.rectangle.angled",
            category: .image,
            inputs: [.image, svg],
            keywords: ["webp", "lossless", "sans perte", "web", "png"]
        ) { inputs, ctx in
            try inputs.map { url in
                let out = ctx.output(for: url, ext: "webp", suffix: url.contentType == .webP ? L("lossless") : nil)
                try WebPEncoder.write(try ImageIOHelpers.load(url), to: out, lossless: true)
                return out
            }
        })

        tools.append(Tool(
            id: "image.favicon",
            title: "Create a favicon pack",
            subtitle: "ICO + PNG 16 to 512 px + HTML code",
            symbol: "globe",
            category: .image,
            inputs: [.image, svg],
            keywords: ["favicon", "site", "web", "icône", "apple-touch-icon", "manifest", "ico", "pwa"]
        ) { inputs, ctx in
            try inputs.map { url in try makeFavicons(from: url) }
        })

        tools.append(Tool(
            id: "image.svg.scales",
            title: "SVG → PNG @1x @2x @3x",
            subtitle: "Sharp exports for apps and Retina screens",
            symbol: "square.3.layers.3d",
            category: .image,
            inputs: [svg],
            keywords: ["svg", "png", "retina", "@2x", "@3x", "export", "ios", "app"]
        ) { inputs, ctx in
            try inputs.map { url in
                guard let image = NSImage(contentsOf: url), image.size.width > 0 else { throw ToolError.unreadable(url) }
                let folder = try PDFTools.makeFolder(for: url, name: "PNG")
                for scale in [1, 2, 3] {
                    let w = Int(image.size.width) * scale, h = Int(image.size.height) * scale
                    guard let ctx = ImageIOHelpers.context(width: w, height: h) else { continue }
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                    image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
                    NSGraphicsContext.restoreGraphicsState()
                    guard let cg = ctx.makeImage() else { continue }
                    let name = scale == 1 ? url.baseName : "\(url.baseName)@\(scale)x"
                    try ImageIOHelpers.write(cg, to: folder.appendingPathComponent(name).appendingPathExtension("png"), type: .png)
                }
                return folder
            }
        })

        tools.append(Tool(
            id: "image.to.pdf",
            title: "Convert to PDF",
            subtitle: "One page per image",
            symbol: "doc.richtext",
            category: .image,
            inputs: [.image, svg],
            excludes: [.pdf],
            keywords: ["pdf", "document"]
        ) { inputs, ctx in
            try inputs.map { url in
                let out = ctx.output(for: url, ext: "pdf")
                try makePDF(from: [url], to: out)
                return out
            }
        })

        tools.append(Tool(
            id: "image.gif.frames",
            title: "Extract GIF frames",
            subtitle: "Each frame as PNG",
            symbol: "square.stack.3d.down.right",
            category: .image,
            inputs: [.gif],
            keywords: ["gif", "frames", "animation", "extraire"]
        ) { inputs, ctx in
            var outputs: [URL] = []
            for url in inputs {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ToolError.unreadable(url) }
                let count = CGImageSourceGetCount(source)
                let folder = OutputLocation.uniqueURL(in: OutputLocation.current.directory(for: url), stem: "\(url.baseName) \(L("frames"))", ext: "")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for index in 0..<count {
                    guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
                    try ImageIOHelpers.write(frame, to: folder.appendingPathComponent(String(format: "frame-%04d.png", index + 1)), type: .png)
                    ctx.progress(Double(index + 1) / Double(count))
                }
                outputs.append(folder)
            }
            return outputs
        })

        return tools
    }

    // MARK: Transformations

    private static func transform(
        id: String, title: String, subtitle: String, symbol: String, keywords: [String],
        suffix: String, forceType: (UTType, String)? = nil, quality: Double? = nil,
        _ apply: @escaping @Sendable (CGImage) throws -> CGImage
    ) -> Tool {
        Tool(id: id, title: title, subtitle: subtitle, symbol: symbol, category: .image,
             inputs: [.image], keywords: keywords) { inputs, ctx in
            try inputs.map { url in
                let image = try apply(try ImageIOHelpers.load(url))
                let (type, ext) = forceType ?? ImageIOHelpers.sameFormat(for: url)
                let out = ctx.output(for: url, ext: ext, suffix: suffix)
                try ImageIOHelpers.write(image, to: out, type: type, quality: quality ?? 0.92)
                return out
            }
        }
    }

    private static var transforms: [Tool] {
        [
            transform(id: "image.half", title: "Shrink by half", subtitle: "50% of the size",
                      symbol: "arrow.down.right.and.arrow.up.left", keywords: ["redimensionner", "resize", "réduire", "50"],
                      suffix: "50%") { ImageIOHelpers.scaled($0, by: 0.5) },
            transform(id: "image.resize.1920", title: "Resize to 1920 px", subtitle: "Longest side",
                      symbol: "aspectratio", keywords: ["redimensionner", "resize", "full hd", "1080p"],
                      suffix: "1920") { ImageIOHelpers.resize($0, maxSide: 1920) },
            transform(id: "image.resize.1080", title: "Resize to 1080 px", subtitle: "Great for social media",
                      symbol: "aspectratio", keywords: ["redimensionner", "resize", "instagram"],
                      suffix: "1080") { ImageIOHelpers.resize($0, maxSide: 1080) },
            transform(id: "image.thumb", title: "512 px thumbnail", subtitle: "Small PNG thumbnail",
                      symbol: "photo.badge.checkmark", keywords: ["miniature", "thumbnail", "vignette"],
                      suffix: L("thumbnail"), forceType: (.png, "png")) { ImageIOHelpers.resize($0, maxSide: 512) },
            transform(id: "image.compress", title: "Compress", subtitle: "60% quality JPEG, smaller file",
                      symbol: "arrow.down.circle", keywords: ["compresser", "compress", "optimiser", "poids", "léger"],
                      suffix: L("compressed"), forceType: (.jpeg, "jpg"), quality: 0.6) { $0 },
            transform(id: "image.mono", title: "Black and white", subtitle: "Monochrome filter",
                      symbol: "circle.lefthalf.filled", keywords: ["noir", "blanc", "gris", "grayscale", "mono"],
                      suffix: L("B&W")) { image in
                let filter = CIFilter.photoEffectNoir()
                filter.inputImage = CIImage(cgImage: image)
                return try ImageIOHelpers.render(filter.outputImage!)
            },
            transform(id: "image.rotate", title: "Rotate 90°", subtitle: "Clockwise",
                      symbol: "rotate.right", keywords: ["rotation", "pivoter", "tourner"],
                      suffix: L("rotated")) { image in
                try ImageIOHelpers.render(CIImage(cgImage: image).oriented(.right))
            },
            transform(id: "image.flip", title: "Flip horizontally", subtitle: "Mirror the image",
                      symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", keywords: ["miroir", "flip", "retourner"],
                      suffix: L("mirrored")) { image in
                try ImageIOHelpers.render(CIImage(cgImage: image).oriented(.upMirrored))
            },
            transform(id: "image.strip", title: "Remove metadata", subtitle: "Strips EXIF, GPS and camera info",
                      symbol: "location.slash", keywords: ["exif", "gps", "métadonnées", "vie privée", "metadata"],
                      suffix: L("no metadata")) { $0 },
        ]
    }

    // MARK: Plusieurs fichiers combinés

    private static var combined: [Tool] {
        [
            Tool(id: "image.merge.pdf", title: "Combine into one PDF", subtitle: "All images, one per page",
                 symbol: "doc.on.doc", category: .image, inputs: [.image, svg],
                 keywords: ["pdf", "fusionner", "assembler", "combiner", "merge"], combinesInputs: true, minimumInputs: 2) { inputs, ctx in
                let out = ctx.output(for: inputs[0], ext: "pdf", suffix: inputs.count > 1 ? L("and %d more", inputs.count - 1) : nil)
                try makePDF(from: inputs, to: out)
                return [out]
            },
            Tool(id: "image.merge.gif", title: "Create an animated GIF", subtitle: "Images become frames",
                 symbol: "play.square.stack", category: .image, inputs: [.image],
                 keywords: ["gif", "animation", "animé", "diaporama"], combinesInputs: true, minimumInputs: 2) { inputs, ctx in
                let frames = try inputs.map { try ImageIOHelpers.load($0, maxPixelSize: 800) }
                let out = ctx.output(for: inputs[0], ext: "gif", suffix: L("animated"))
                try ImageIOHelpers.writeMulti(frames, to: out, type: .gif, frameDelay: 0.5)
                return [out]
            },
        ]
    }

    /// Pack favicon complet pour un site web, avec le code HTML à coller.
    static func makeFavicons(from url: URL) throws -> URL {
        let image = try ImageIOHelpers.load(url)
        let folder = try PDFTools.makeFolder(for: url, name: "favicon")
        let pngs: [(String, Int)] = [
            ("favicon-16x16.png", 16), ("favicon-32x32.png", 32), ("favicon-48x48.png", 48),
            ("apple-touch-icon.png", 180), ("android-chrome-192x192.png", 192), ("android-chrome-512x512.png", 512),
        ]
        for (name, size) in pngs {
            try ImageIOHelpers.write(ImageIOHelpers.resize(image, maxSide: size, square: true),
                                     to: folder.appendingPathComponent(name), type: .png)
        }
        try ImageIOHelpers.writeMulti([16, 32, 48].map { ImageIOHelpers.resize(image, maxSide: $0, square: true) },
                                      to: folder.appendingPathComponent("favicon.ico"), type: .ico)
        let manifest = """
        {
          "name": "",
          "short_name": "",
          "icons": [
            { "src": "/android-chrome-192x192.png", "sizes": "192x192", "type": "image/png" },
            { "src": "/android-chrome-512x512.png", "sizes": "512x512", "type": "image/png" }
          ],
          "display": "standalone"
        }

        """
        try manifest.write(to: folder.appendingPathComponent("site.webmanifest"), atomically: true, encoding: .utf8)
        let html = """
        <link rel="icon" href="/favicon.ico" sizes="48x48">
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
        <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
        <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
        <link rel="manifest" href="/site.webmanifest">

        """
        try html.write(to: folder.appendingPathComponent("favicon.html"), atomically: true, encoding: .utf8)
        return folder
    }

    static func makePDF(from urls: [URL], to out: URL) throws {
        let document = PDFDocument()
        for url in urls {
            let image = try ImageIOHelpers.load(url)
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            guard let page = PDFPage(image: nsImage) else { throw ToolError.failed(L("Could not create the PDF page.")) }
            document.insert(page, at: document.pageCount)
        }
        guard document.write(to: out) else { throw ToolError.failed(L("Failed to write the PDF.")) }
    }
}
