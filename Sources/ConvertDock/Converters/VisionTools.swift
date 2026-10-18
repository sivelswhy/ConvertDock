import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import Vision

/// Outils « intelligents » basés sur Vision et Core Image, 100 % sur l'appareil.
enum VisionTools {
    static var all: [Tool] {
        [
            Tool(id: "ai.removebg", title: "Remove background", subtitle: "Automatic subject cutout → PNG",
                 symbol: "person.crop.circle.badge.minus", category: .intelligence, inputs: [.image],
                 keywords: ["background", "remover", "détourer", "fond", "transparent", "arrière-plan", "remove bg"]) { inputs, ctx in
                try await inputs.asyncMap { url in
                    let image = try await removeBackgroundOrAsk(url, crop: false)
                    let out = ctx.output(for: url, ext: "png", suffix: L("cutout"))
                    try ImageIOHelpers.write(image, to: out, type: .png)
                    return out
                }
            },
            Tool(id: "ai.removebg.crop", title: "Cut out and crop", subtitle: "Isolated subject, tightly cropped",
                 symbol: "crop", category: .intelligence, inputs: [.image],
                 keywords: ["background", "remover", "sticker", "autocollant", "recadrer", "fond"]) { inputs, ctx in
                try await inputs.asyncMap { url in
                    let image = try await removeBackgroundOrAsk(url, crop: true)
                    let out = ctx.output(for: url, ext: "png", suffix: "sticker")
                    try ImageIOHelpers.write(image, to: out, type: .png)
                    return out
                }
            },
            Tool(id: "ai.removebg.manual", title: "Manual cutout", subtitle: "Magic wand and brush, for touch-ups",
                 symbol: "wand.and.stars", category: .intelligence, inputs: [.image],
                 keywords: ["background", "remover", "fond", "détourer", "détourage", "baguette", "magique", "pinceau", "gomme", "manuel", "retoucher", "sélectionner"]) { inputs, ctx in
                try await inputs.asyncMap { url in
                    guard await isInteractive else { throw ToolError.unsupported(L("Manual cutout requires the graphical interface.")) }
                    let image = try ImageIOHelpers.load(url, maxPixelSize: editorMaxSize)
                    let mask = try? subjectMask(image)
                    guard let result = await BackgroundEditor.present(
                        url, image: image, initialMask: mask,
                        message: mask == nil ? L("Click the background with the magic wand to remove it.") : nil
                    ) else { throw CancellationError() }
                    let out = ctx.output(for: url, ext: "png", suffix: L("cutout"))
                    try ImageIOHelpers.write(result, to: out, type: .png)
                    return out
                }
            },
            Tool(id: "ai.vectorize.color", title: "Vectorize to SVG (color)", subtitle: "PNG/JPEG → SVG, 8 colors",
                 symbol: "scribble.variable", category: .intelligence, inputs: [.image], excludes: [.svg],
                 keywords: ["svg", "vecteur", "vectoriser", "tracer", "png to svg", "vector", "trace"]) { inputs, ctx in
                try inputs.map { url in
                    let out = ctx.output(for: url, ext: "svg")
                    try Vectorizer.vectorize(url, to: out, colors: 8, progress: ctx.progress)
                    return out
                }
            },
            Tool(id: "ai.vectorize.mono", title: "Vectorize to SVG (black & white)", subtitle: "Great for logos and drawings",
                 symbol: "signature", category: .intelligence, inputs: [.image], excludes: [.svg],
                 keywords: ["svg", "vecteur", "vectoriser", "logo", "png to svg", "silhouette", "trace"]) { inputs, ctx in
                try inputs.map { url in
                    let out = ctx.output(for: url, ext: "svg", suffix: L("B&W"))
                    try Vectorizer.vectorize(url, to: out, colors: 1, progress: ctx.progress)
                    return out
                }
            },
            Tool(id: "ai.ocr", title: "Extract text (OCR)", subtitle: "Text recognition → .txt",
                 symbol: "text.viewfinder", category: .intelligence, inputs: [.image],
                 keywords: ["ocr", "texte", "reconnaissance", "scanner", "copier", "lire"]) { inputs, ctx in
                try inputs.map { url in
                    let text = try recognizeText(try ImageIOHelpers.load(url))
                    let out = ctx.output(for: url, ext: "txt")
                    try text.write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "ai.blurfaces", title: "Blur faces", subtitle: "Automatically anonymizes a photo",
                 symbol: "eye.slash", category: .intelligence, inputs: [.image],
                 keywords: ["flou", "visage", "anonymiser", "blur", "face", "vie privée"]) { inputs, ctx in
                try inputs.map { url in
                    let (type, ext) = ImageIOHelpers.sameFormat(for: url)
                    let out = ctx.output(for: url, ext: ext, suffix: L("anonymized"))
                    try ImageIOHelpers.write(try blurFaces(try ImageIOHelpers.load(url)), to: out, type: type, quality: 0.92)
                    return out
                }
            },
            Tool(id: "ai.upscale", title: "Upscale ×2", subtitle: "High-quality Lanczos upscaling",
                 symbol: "arrow.up.left.and.arrow.down.right", category: .intelligence, inputs: [.image],
                 keywords: ["upscale", "agrandir", "résolution", "zoom", "x2"]) { inputs, ctx in
                try inputs.map { url in
                    let image = CIImage(cgImage: try ImageIOHelpers.load(url))
                    let filter = CIFilter.lanczosScaleTransform()
                    filter.inputImage = image
                    filter.scale = 2
                    filter.aspectRatio = 1
                    let sharpen = CIFilter.sharpenLuminance()
                    sharpen.inputImage = filter.outputImage
                    sharpen.sharpness = 0.4
                    let (type, ext) = ImageIOHelpers.sameFormat(for: url)
                    let out = ctx.output(for: url, ext: ext, suffix: "x2")
                    try ImageIOHelpers.write(try ImageIOHelpers.render(sharpen.outputImage!), to: out, type: type, quality: 0.92)
                    return out
                }
            },
        ]
    }

    static let editorMaxSize = 2400

    @MainActor static var isInteractive: Bool { NSApp.activationPolicy() != .prohibited }

    /// Détourage automatique ; si aucun sujet n'est trouvé, ouvre l'éditeur manuel (baguette magique / pinceau).
    static func removeBackgroundOrAsk(_ url: URL, crop: Bool) async throws -> CGImage {
        do {
            return try removeBackground(url, crop: crop)
        } catch ToolError.noSubject {
            guard await isInteractive else { throw ToolError.noSubject(url) }
            let image = try ImageIOHelpers.load(url, maxPixelSize: editorMaxSize)
            guard let result = await BackgroundEditor.present(
                url, image: image, initialMask: nil,
                message: L("No subject was detected automatically. Click the background with the magic wand to remove it.")
            ) else { throw CancellationError() }
            return crop ? cropToContent(result) : result
        }
    }

    /// Masque du sujet (0–255 par pixel) aux dimensions de l'image, ou `nil` si rien n'est détecté.
    static func subjectMask(_ image: CGImage) throws -> [UInt8]? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
        let buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w == image.width, h == image.height, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var mask = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<w { mask[y * w + x] = UInt8(min(max(row[x], 0), 1) * 255) }
        }
        return mask
    }

    /// Recadre une image sur ses pixels non transparents.
    static func cropToContent(_ image: CGImage) -> CGImage {
        guard let ctx = ImageIOHelpers.context(width: image.width, height: image.height), let data = ctx.data else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let px = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let row = ctx.bytesPerRow
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width where px[y * row + x * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        // Les lignes du contexte bitmap partent du haut, comme CGImage.cropping.
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? image
    }

    static func removeBackground(_ url: URL, crop: Bool) throws -> CGImage {
        let image = try ImageIOHelpers.load(url)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw ToolError.noSubject(url)
        }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: crop)
        return try ImageIOHelpers.render(CIImage(cvPixelBuffer: buffer))
    }

    static func recognizeText(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { throw ToolError.failed(L("No text detected.")) }
        return lines.joined(separator: "\n")
    }

    static func blurFaces(_ image: CGImage) throws -> CGImage {
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        let faces = request.results ?? []
        guard !faces.isEmpty else { throw ToolError.failed(L("No face detected.")) }

        let base = CIImage(cgImage: image)
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let blurred = base.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(w, h)) / 40)
            .cropped(to: base.extent)

        // Masque : ellipses blanches adoucies sur fond noir.
        var mask = CIImage(color: .black).cropped(to: base.extent)
        for face in faces {
            let box = face.boundingBox
            let rect = CGRect(x: box.minX * w, y: box.minY * h, width: box.width * w, height: box.height * h)
                .insetBy(dx: -box.width * w * 0.2, dy: -box.height * h * 0.25)
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: rect.midX, y: rect.midY)
            gradient.radius0 = Float(max(rect.width, rect.height) * 0.45)
            gradient.radius1 = Float(max(rect.width, rect.height) * 0.6)
            gradient.color0 = .white
            gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            mask = gradient.outputImage!.cropped(to: base.extent).composited(over: mask)
        }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = blurred
        blend.backgroundImage = base
        blend.maskImage = mask
        return try ImageIOHelpers.render(blend.outputImage!)
    }
}
