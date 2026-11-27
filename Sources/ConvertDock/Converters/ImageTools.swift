import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit
import Vision
import UniformTypeIdentifiers

enum ImageTools {
    private static let raster: [UTType] = [.image]
    /// Images dont ImageIO/NSImage savent produire un bitmap.
    private static let svg = UTType.svg

    static var all: [Tool] {
        conversions + transforms + combined + extras
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
            transform(id: "image.rotate.left", title: "Rotate 90° left", subtitle: "Counterclockwise",
                      symbol: "rotate.left", keywords: ["rotation", "pivoter", "tourner", "gauche"],
                      suffix: L("rotated")) { image in
                try ImageIOHelpers.render(CIImage(cgImage: image).oriented(.left))
            },
            transform(id: "image.flip.vertical", title: "Flip vertically", subtitle: "Upside-down mirror",
                      symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down", keywords: ["miroir", "flip", "retourner", "vertical"],
                      suffix: L("mirrored")) { image in
                try ImageIOHelpers.render(CIImage(cgImage: image).oriented(.downMirrored))
            },
            transform(id: "image.square", title: "Crop to square", subtitle: "Centered, for profile pictures",
                      symbol: "crop", keywords: ["carré", "square", "recadrer", "crop", "avatar", "profil", "instagram"],
                      suffix: L("square")) { image in
                let side = min(image.width, image.height)
                let rect = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
                guard let cropped = image.cropping(to: rect) else { throw ToolError.failed(L("Failed to render the image.")) }
                return cropped
            },
            transform(id: "image.invert", title: "Invert colors", subtitle: "Photo negative",
                      symbol: "circle.righthalf.filled.inverse", keywords: ["inverser", "négatif", "invert", "couleurs"],
                      suffix: L("inverted")) { image in
                let filter = CIFilter.colorInvert()
                filter.inputImage = CIImage(cgImage: image)
                return try ImageIOHelpers.render(filter.outputImage!)
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

    // MARK: Autres outils

    private static var extras: [Tool] {
        [
            Tool(id: "image.watermark", title: "Add a watermark", subtitle: "Your text in the bottom-right corner",
                 symbol: "signature", category: .image, inputs: [.image],
                 keywords: ["filigrane", "watermark", "copyright", "signature", "texte", "protéger"],
                 configure: { url in await TextPrompt.watermark(url) }) { inputs, ctx in
                let label = ctx.parameters.text ?? "©"
                return try inputs.map { url in
                    let image = try ImageIOHelpers.load(url)
                    guard let canvas = ImageIOHelpers.context(width: image.width, height: image.height) else {
                        throw ToolError.failed(L("Failed to render the image."))
                    }
                    canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    let shadow = NSShadow()
                    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
                    shadow.shadowBlurRadius = 4
                    let size = max(12, CGFloat(min(image.width, image.height)) / 22)
                    let text = NSAttributedString(string: label, attributes: [
                        .font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: NSColor.white.withAlphaComponent(0.85), .shadow: shadow,
                    ])
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
                    let textSize = text.size()
                    text.draw(at: CGPoint(x: CGFloat(image.width) - textSize.width - size, y: size * 0.8))
                    NSGraphicsContext.restoreGraphicsState()
                    guard let result = canvas.makeImage() else { throw ToolError.failed(L("Failed to render the image.")) }
                    let (type, ext) = ImageIOHelpers.sameFormat(for: url)
                    let out = ctx.output(for: url, ext: ext, suffix: L("watermarked"))
                    try ImageIOHelpers.write(result, to: out, type: type, quality: 0.92)
                    return out
                }
            },
            Tool(id: "image.exif", title: "Show metadata (EXIF)", subtitle: "Camera, date, GPS, settings → .txt",
                 symbol: "info.circle", category: .image, inputs: [.image],
                 keywords: ["exif", "métadonnées", "metadata", "gps", "appareil", "infos", "date"]) { inputs, ctx in
                try inputs.map { url in
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { throw ToolError.unreadable(url) }
                    var lines = [url.lastPathComponent, ""]
                    func walk(_ dict: [String: Any], prefix: String) {
                        for key in dict.keys.sorted() {
                            let value = dict[key]!
                            if let child = value as? [String: Any] {
                                walk(child, prefix: "\(prefix)\(key.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")) › ")
                            } else if let array = value as? [Any] {
                                lines.append("\(prefix)\(key): \(array.map { "\($0)" }.joined(separator: ", "))")
                            } else {
                                lines.append("\(prefix)\(key): \(value)")
                            }
                        }
                    }
                    walk(props, prefix: "")
                    let out = ctx.output(for: url, ext: "txt", suffix: "EXIF")
                    try lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "image.palette", title: "Extract color palette", subtitle: "8 dominant colors → SVG + hex codes",
                 symbol: "paintpalette", category: .image, inputs: [.image, svg],
                 keywords: ["palette", "couleurs", "colors", "hex", "nuancier", "dominantes", "design"]) { inputs, ctx in
                try inputs.flatMap { url in
                    let colors = try palette(ImageIOHelpers.load(url, maxPixelSize: 128))
                    let hex = colors.map { String(format: "#%02X%02X%02X", $0.r, $0.g, $0.b) }
                    let swatches = hex.enumerated().map { i, color in
                        "<rect x=\"\(i * 100)\" y=\"0\" width=\"100\" height=\"100\" fill=\"\(color)\"/>"
                        + "<text x=\"\(i * 100 + 50)\" y=\"125\" text-anchor=\"middle\" font-family=\"Menlo\" font-size=\"13\">\(color)</text>"
                    }.joined(separator: "\n")
                    let svgText = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(hex.count * 100)\" height=\"140\">\n"
                        + "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>\n\(swatches)\n</svg>\n"
                    let svgOut = ctx.output(for: url, ext: "svg", suffix: L("palette"))
                    try svgText.write(to: svgOut, atomically: true, encoding: .utf8)
                    let txtOut = ctx.output(for: url, ext: "txt", suffix: L("palette"))
                    try (hex.joined(separator: "\n") + "\n").write(to: txtOut, atomically: true, encoding: .utf8)
                    return [svgOut, txtOut]
                }
            },
            Tool(id: "image.qr.read", title: "Read QR code / barcode", subtitle: "Content → .txt",
                 symbol: "qrcode.viewfinder", category: .image, inputs: [.image, .pdf],
                 keywords: ["qr", "qr code", "code-barres", "barcode", "scanner", "lire", "décoder"]) { inputs, ctx in
                try inputs.map { url in
                    let request = VNDetectBarcodesRequest()
                    try VNImageRequestHandler(cgImage: try ImageIOHelpers.load(url), options: [:]).perform([request])
                    let payloads = (request.results ?? []).compactMap(\.payloadStringValue)
                    guard !payloads.isEmpty else { throw ToolError.failed(L("No QR code or barcode detected.")) }
                    let out = ctx.output(for: url, ext: "txt", suffix: "QR")
                    try (NSOrderedSet(array: payloads).array as! [String]).joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "image.qr.make", title: "Create a QR code", subtitle: "From the text or link in the file → PNG",
                 symbol: "qrcode", category: .image, inputs: [.plainText, .internetLocation],
                 keywords: ["qr", "qr code", "générer", "créer", "lien", "url", "wifi"]) { inputs, ctx in
                try inputs.map { url in
                    var text = try String(contentsOf: url, encoding: .utf8)
                    if url.pathExtension.lowercased() == "webloc",
                       let plist = try? PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any],
                       let link = plist["URL"] as? String { text = link }
                    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let filter = CIFilter.qrCodeGenerator()
                    filter.message = Data(text.utf8)
                    filter.correctionLevel = "M"
                    guard !text.isEmpty, let code = filter.outputImage else { throw ToolError.failed(L("Text too long for a QR code.")) }
                    // Agrandi sans lissage, avec une marge blanche de 4 modules.
                    let scale = max(1, (1024 / code.extent.width).rounded(.down))
                    let scaled = code.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    let margin = 4 * scale
                    let framed = scaled.transformed(by: CGAffineTransform(translationX: margin, y: margin))
                        .composited(over: CIImage(color: .white).cropped(to: scaled.extent.insetBy(dx: -margin, dy: -margin).offsetBy(dx: margin, dy: margin)))
                    let out = ctx.output(for: url, ext: "png", suffix: "QR")
                    try ImageIOHelpers.write(try ImageIOHelpers.render(framed), to: out, type: .png)
                    return out
                }
            },
        ]
    }

    /// Couleurs dominantes : histogramme sur une grille de 16 niveaux par canal, couleurs trop proches fusionnées.
    static func palette(_ image: CGImage, count: Int = 8) throws -> [(r: Int, g: Int, b: Int)] {
        let w = image.width, h = image.height
        guard let canvas = ImageIOHelpers.context(width: w, height: h) else { throw ToolError.failed(L("Could not read pixels.")) }
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = canvas.data else { throw ToolError.failed(L("Could not read pixels.")) }
        let pixels = data.bindMemory(to: UInt8.self, capacity: canvas.bytesPerRow * h)
        var buckets: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for y in 0..<h {
            for x in 0..<w {
                let i = y * canvas.bytesPerRow + x * 4
                let a = Int(pixels[i + 3])
                guard a > 127 else { continue }
                // Prémultiplié : on divise par l'alpha.
                let r = Int(pixels[i]) * 255 / a, g = Int(pixels[i + 1]) * 255 / a, b = Int(pixels[i + 2]) * 255 / a
                let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
                let e = buckets[key] ?? (0, 0, 0, 0)
                buckets[key] = (e.n + 1, e.r + r, e.g + g, e.b + b)
            }
        }
        var result: [(r: Int, g: Int, b: Int)] = []
        for e in buckets.values.sorted(by: { $0.n > $1.n }) {
            let c = (r: e.r / e.n, g: e.g / e.n, b: e.b / e.n)
            let distinct = result.allSatisfy { abs($0.r - c.r) + abs($0.g - c.g) + abs($0.b - c.b) > 60 }
            if distinct { result.append(c) }
            if result.count == count { break }
        }
        guard !result.isEmpty else { throw ToolError.failed(L("Could not read pixels.")) }
        return result
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
