import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import Vision

/// Outils « intelligents » basés sur Vision et Core Image, 100 % sur l'appareil.
enum VisionTools {
    static var all: [Tool] {
        [
            Tool(id: "ai.removebg", title: "Supprimer l'arrière-plan", subtitle: "Détourage automatique du sujet → PNG",
                 symbol: "person.crop.circle.badge.minus", category: .intelligence, inputs: [.image],
                 keywords: ["background", "remover", "détourer", "fond", "transparent", "arrière-plan", "remove bg"]) { inputs, ctx in
                try inputs.map { url in
                    let out = ctx.output(for: url, ext: "png", suffix: "détouré")
                    try ImageIOHelpers.write(try removeBackground(url, crop: false), to: out, type: .png)
                    return out
                }
            },
            Tool(id: "ai.removebg.crop", title: "Détourer et recadrer", subtitle: "Sujet isolé, cadré au plus près",
                 symbol: "crop", category: .intelligence, inputs: [.image],
                 keywords: ["background", "remover", "sticker", "autocollant", "recadrer", "fond"]) { inputs, ctx in
                try inputs.map { url in
                    let out = ctx.output(for: url, ext: "png", suffix: "sticker")
                    try ImageIOHelpers.write(try removeBackground(url, crop: true), to: out, type: .png)
                    return out
                }
            },
            Tool(id: "ai.vectorize.color", title: "Vectoriser en SVG (couleur)", subtitle: "PNG/JPEG → SVG, 8 couleurs",
                 symbol: "scribble.variable", category: .intelligence, inputs: [.image], excludes: [.svg],
                 keywords: ["svg", "vecteur", "vectoriser", "tracer", "png to svg", "vector", "trace"]) { inputs, ctx in
                try inputs.map { url in
                    let out = ctx.output(for: url, ext: "svg")
                    try Vectorizer.vectorize(url, to: out, colors: 8, progress: ctx.progress)
                    return out
                }
            },
            Tool(id: "ai.vectorize.mono", title: "Vectoriser en SVG (noir & blanc)", subtitle: "Idéal pour logos et dessins",
                 symbol: "signature", category: .intelligence, inputs: [.image], excludes: [.svg],
                 keywords: ["svg", "vecteur", "vectoriser", "logo", "png to svg", "silhouette", "trace"]) { inputs, ctx in
                try inputs.map { url in
                    let out = ctx.output(for: url, ext: "svg", suffix: "N&B")
                    try Vectorizer.vectorize(url, to: out, colors: 1, progress: ctx.progress)
                    return out
                }
            },
            Tool(id: "ai.ocr", title: "Extraire le texte (OCR)", subtitle: "Reconnaissance de texte → .txt",
                 symbol: "text.viewfinder", category: .intelligence, inputs: [.image],
                 keywords: ["ocr", "texte", "reconnaissance", "scanner", "copier", "lire"]) { inputs, ctx in
                try inputs.map { url in
                    let text = try recognizeText(try ImageIOHelpers.load(url))
                    let out = ctx.output(for: url, ext: "txt")
                    try text.write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "ai.blurfaces", title: "Flouter les visages", subtitle: "Anonymise automatiquement une photo",
                 symbol: "eye.slash", category: .intelligence, inputs: [.image],
                 keywords: ["flou", "visage", "anonymiser", "blur", "face", "vie privée"]) { inputs, ctx in
                try inputs.map { url in
                    let (type, ext) = ImageIOHelpers.sameFormat(for: url)
                    let out = ctx.output(for: url, ext: ext, suffix: "anonymisé")
                    try ImageIOHelpers.write(try blurFaces(try ImageIOHelpers.load(url)), to: out, type: type, quality: 0.92)
                    return out
                }
            },
            Tool(id: "ai.upscale", title: "Agrandir ×2", subtitle: "Mise à l'échelle Lanczos haute qualité",
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

    static func removeBackground(_ url: URL, crop: Bool) throws -> CGImage {
        let image = try ImageIOHelpers.load(url)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw ToolError.failed("Aucun sujet détecté dans « \(url.lastPathComponent) ».")
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
        guard !lines.isEmpty else { throw ToolError.failed("Aucun texte détecté.") }
        return lines.joined(separator: "\n")
    }

    static func blurFaces(_ image: CGImage) throws -> CGImage {
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        let faces = request.results ?? []
        guard !faces.isEmpty else { throw ToolError.failed("Aucun visage détecté.") }

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
