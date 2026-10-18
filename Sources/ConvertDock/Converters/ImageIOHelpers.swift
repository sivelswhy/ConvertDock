import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Lecture / écriture d'images basées sur ImageIO.
enum ImageIOHelpers {
    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Charge une image en appliquant l'orientation EXIF, éventuellement réduite.
    static func load(_ url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ToolError.unreadable(url) }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 4096
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 4096
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize.map { min($0, max(width, height)) } ?? max(width, height),
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return image
        }
        // Formats vectoriels (PDF, SVG) : passer par NSImage.
        if let nsImage = NSImage(contentsOf: url) {
            var rect = CGRect(origin: .zero, size: nsImage.size)
            if let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) { return cg }
        }
        throw ToolError.unreadable(url)
    }

    /// Images (frames) contenues dans un fichier, ex. GIF animé ou TIFF multipage.
    static func frameCount(_ url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double? = nil) throws {
        let needsOpaque = type.conforms(to: .jpeg) || type == .bmp
        let finalImage = needsOpaque ? flatten(image) : image
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ToolError.unsupported("Le format \(type.preferredFilenameExtension ?? type.identifier) n'est pas pris en charge en écriture.")
        }
        var props: [CFString: Any] = [:]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, finalImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ToolError.failed("Échec de l'écriture de \(url.lastPathComponent).") }
    }

    /// Écrit plusieurs images dans un même fichier (GIF animé, ICNS, ICO, TIFF multipage).
    static func writeMulti(_ images: [CGImage], to url: URL, type: UTType, frameDelay: Double? = nil) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, images.count, nil) else {
            throw ToolError.unsupported("Format non pris en charge.")
        }
        if let frameDelay {
            let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
            CGImageDestinationSetProperties(dest, fileProps as CFDictionary)
            let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]]
            for image in images { CGImageDestinationAddImage(dest, image, frameProps as CFDictionary) }
        } else {
            for image in images { CGImageDestinationAddImage(dest, image, nil) }
        }
        guard CGImageDestinationFinalize(dest) else { throw ToolError.failed("Échec de l'écriture de \(url.lastPathComponent).") }
    }

    static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// Composite sur fond blanc (pour les formats sans transparence).
    static func flatten(_ image: CGImage) -> CGImage {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst,
              let ctx = context(width: image.width, height: image.height) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(.white)
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    /// Redimensionne pour tenir dans `maxSide` (ou exactement au carré si `square`).
    static func resize(_ image: CGImage, maxSide: Int, square: Bool = false) -> CGImage {
        let scale = Double(maxSide) / Double(max(image.width, image.height))
        if !square && scale >= 1 { return image }
        let w = square ? maxSide : max(1, Int(Double(image.width) * scale))
        let h = square ? maxSide : max(1, Int(Double(image.height) * scale))
        guard let ctx = context(width: w, height: h) else { return image }
        ctx.interpolationQuality = .high
        var rect = CGRect(x: 0, y: 0, width: w, height: h)
        if square {
            // Conserve les proportions, centré, fond transparent.
            let fit = min(Double(w) / Double(image.width), Double(h) / Double(image.height))
            let fw = Double(image.width) * fit, fh = Double(image.height) * fit
            rect = CGRect(x: (Double(w) - fw) / 2, y: (Double(h) - fh) / 2, width: fw, height: fh)
        }
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    static func scaled(_ image: CGImage, by factor: Double) -> CGImage {
        resize(image, maxSide: max(1, Int(Double(max(image.width, image.height)) * factor)))
    }

    static func render(_ ci: CIImage) throws -> CGImage {
        guard let cg = ciContext.createCGImage(ci, from: ci.extent.integral, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw ToolError.failed("Échec du rendu de l'image.")
        }
        return cg
    }

    /// Type de sortie « naturel » pour réécrire une image dans son propre format.
    static func sameFormat(for url: URL) -> (UTType, String) {
        if let type = url.contentType, (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(type.identifier) {
            return (type, url.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "png") : url.pathExtension)
        }
        return (.png, "png")
    }
}
