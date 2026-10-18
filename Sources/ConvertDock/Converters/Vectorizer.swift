import CoreGraphics
import Foundation
import Vision

/// Vectorisation d'images bitmap en SVG.
///
/// 1. Quantification des couleurs (k-means) ou seuillage d'Otsu en mode monochrome.
/// 2. Pour chaque couleur, un masque est tracé par `VNDetectContoursRequest`.
/// 3. Les contours sont simplifiés puis lissés en courbes quadratiques.
enum Vectorizer {
    private struct RGB { var r: Float, g: Float, b: Float }

    static func vectorize(_ url: URL, to out: URL, colors: Int, progress: @Sendable (Double) -> Void) throws {
        let image = try ImageIOHelpers.load(url, maxPixelSize: 1024)
        let w = image.width, h = image.height
        guard let ctx = ImageIOHelpers.context(width: w, height: h) else { throw ToolError.failed(L("Not enough memory.")) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { throw ToolError.failed(L("Could not read pixels.")) }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let count = w * h

        // labels[i] = index de couleur, ou 255 pour un pixel transparent.
        var labels = [UInt8](repeating: 255, count: count)
        var palette: [RGB] = []

        func pixel(_ i: Int) -> (RGB, UInt8) {
            let a = pixels[i * 4 + 3]
            guard a > 0 else { return (RGB(r: 0, g: 0, b: 0), 0) }
            let k = 255 / Float(a)
            return (RGB(r: Float(pixels[i * 4]) * k, g: Float(pixels[i * 4 + 1]) * k, b: Float(pixels[i * 4 + 2]) * k), a)
        }

        if colors <= 1 {
            // Seuil d'Otsu sur la luminance, les pixels sombres forment la forme.
            var lum = [UInt8](repeating: 255, count: count)
            var histogram = [Int](repeating: 0, count: 256)
            for i in 0..<count {
                let (c, a) = pixel(i)
                guard a >= 128 else { continue }
                let l = UInt8(min(255, 0.299 * c.r + 0.587 * c.g + 0.114 * c.b))
                lum[i] = l
                histogram[Int(l)] += 1
            }
            let threshold = otsu(histogram)
            for i in 0..<count where lum[i] <= threshold && pixel(i).1 >= 128 { labels[i] = 0 }
            palette = [RGB(r: 0, g: 0, b: 0)]
        } else {
            palette = kMeans(count: count, k: colors, pixel: pixel)
            for i in 0..<count {
                let (c, a) = pixel(i)
                guard a >= 128 else { continue }
                labels[i] = UInt8(nearest(c, in: palette))
            }
        }
        progress(0.2)

        // Ordre de dessin : les couleurs les plus présentes d'abord (fond), les détails ensuite.
        var areas = [Int](repeating: 0, count: palette.count)
        for l in labels where l != 255 { areas[Int(l)] += 1 }
        let order = palette.indices.filter { areas[$0] > 0 }.sorted { areas[$0] > areas[$1] }

        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(w) \(h)" width="\(w)" height="\(h)">

        """
        var mask = [UInt8](repeating: 255, count: count)
        for (step, index) in order.enumerated() {
            for i in 0..<count { mask[i] = labels[i] == UInt8(index) ? 0 : 255 }
            let pathData = try trace(mask: mask, width: w, height: h)
            if !pathData.isEmpty {
                let c = palette[index]
                let hex = String(format: "#%02X%02X%02X", Int(c.r.rounded()), Int(c.g.rounded()), Int(c.b.rounded()))
                let stroke = colors > 1 ? " stroke=\"\(hex)\" stroke-width=\"0.8\" stroke-linejoin=\"round\"" : ""
                svg += "  <path fill=\"\(hex)\" fill-rule=\"evenodd\"\(stroke) d=\"\(pathData)\"/>\n"
            }
            progress(0.2 + 0.8 * Double(step + 1) / Double(order.count))
        }
        svg += "</svg>\n"
        try svg.write(to: out, atomically: true, encoding: .utf8)
    }

    private static func trace(mask: [UInt8], width w: Int, height h: Int) throws -> String {
        let image: CGImage? = mask.withUnsafeBufferPointer { buffer in
            guard let provider = CGDataProvider(data: Data(buffer: buffer) as CFData) else { return nil }
            return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                           space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        guard let image else { return "" }

        let request = VNDetectContoursRequest()
        request.detectsDarkOnLight = true
        request.contrastAdjustment = 1
        request.maximumImageDimension = max(w, h)
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let observation = request.results?.first else { return "" }

        var d = ""
        let fw = Float(w), fh = Float(h)
        for index in 0..<observation.contourCount {
            guard let contour = try? observation.contour(at: index),
                  let simplified = try? contour.polygonApproximation(epsilon: 0.0012) else { continue }
            let points = simplified.normalizedPoints.map { SIMD2<Float>($0.x * fw, (1 - $0.y) * fh) }
            guard points.count >= 3, abs(area(points)) >= 6 else { continue }
            d += smoothPath(points)
        }
        return d
    }

    /// Courbe fermée passant par les milieux des segments, avec les sommets comme points de contrôle.
    /// Les angles vifs (> 60°) sont conservés en segments droits.
    private static func smoothPath(_ p: [SIMD2<Float>]) -> String {
        func f(_ v: Float) -> String { String(format: "%.1f", v) }
        func mid(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> SIMD2<Float> { (a + b) / 2 }
        func isCorner(_ i: Int) -> Bool {
            let a = p[i] - p[(i - 1 + n) % n], b = p[(i + 1) % n] - p[i]
            let la = (a * a).sum().squareRoot(), lb = (b * b).sum().squareRoot()
            guard la > 0, lb > 0 else { return false }
            return (a * b).sum() / (la * lb) < 0.5
        }
        let n = p.count
        let start = mid(p[n - 1], p[0])
        var d = "M\(f(start.x)) \(f(start.y))"
        for i in 0..<n {
            let m = mid(p[i], p[(i + 1) % n])
            if isCorner(i) {
                d += "L\(f(p[i].x)) \(f(p[i].y))L\(f(m.x)) \(f(m.y))"
            } else {
                d += "Q\(f(p[i].x)) \(f(p[i].y)) \(f(m.x)) \(f(m.y))"
            }
        }
        return d + "Z"
    }

    private static func area(_ p: [SIMD2<Float>]) -> Float {
        var sum: Float = 0
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    private static func otsu(_ histogram: [Int]) -> UInt8 {
        let total = histogram.reduce(0, +)
        guard total > 0 else { return 128 }
        let sum = histogram.enumerated().reduce(0.0) { $0 + Double($1.offset * $1.element) }
        var sumB = 0.0, weightB = 0, best = 0.0, threshold = 128
        for t in 0..<256 {
            weightB += histogram[t]
            guard weightB > 0 else { continue }
            let weightF = total - weightB
            if weightF == 0 { break }
            sumB += Double(t * histogram[t])
            let meanB = sumB / Double(weightB), meanF = (sum - sumB) / Double(weightF)
            let between = Double(weightB) * Double(weightF) * (meanB - meanF) * (meanB - meanF)
            if between > best { best = between; threshold = t }
        }
        return UInt8(threshold)
    }

    private static func nearest(_ c: RGB, in palette: [RGB]) -> Int {
        var best = 0
        var bestDistance = Float.greatestFiniteMagnitude
        for (i, p) in palette.enumerated() {
            let dr = c.r - p.r, dg = c.g - p.g, db = c.b - p.b
            let distance = dr * dr * 0.3 + dg * dg * 0.59 + db * db * 0.11
            if distance < bestDistance { bestDistance = distance; best = i }
        }
        return best
    }

    /// k-means sur un échantillon de pixels opaques, initialisation k-means++ déterministe.
    private static func kMeans(count: Int, k: Int, pixel: (Int) -> (RGB, UInt8)) -> [RGB] {
        var generator = SplitMix(seed: 42)
        var samples: [RGB] = []
        let stride = max(1, count / 30_000)
        for i in Swift.stride(from: 0, to: count, by: stride) {
            let (c, a) = pixel(i)
            if a >= 128 { samples.append(c) }
        }
        guard !samples.isEmpty else { return [RGB(r: 0, g: 0, b: 0)] }

        var centers = [samples[Int(generator.next() % UInt64(samples.count))]]
        while centers.count < k {
            let distances = samples.map { s -> Float in
                let c = centers[nearest(s, in: centers)]
                return (s.r - c.r) * (s.r - c.r) + (s.g - c.g) * (s.g - c.g) + (s.b - c.b) * (s.b - c.b)
            }
            let total = distances.reduce(0, +)
            guard total > 0 else { break }
            var target = Float(Double(generator.next() % 1_000_000) / 1_000_000) * total
            var chosen = samples.count - 1
            for (i, d) in distances.enumerated() {
                target -= d
                if target <= 0 { chosen = i; break }
            }
            centers.append(samples[chosen])
        }

        for _ in 0..<12 {
            var sums = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: centers.count)
            var counts = [Int](repeating: 0, count: centers.count)
            for s in samples {
                let i = nearest(s, in: centers)
                sums[i].r += s.r; sums[i].g += s.g; sums[i].b += s.b
                counts[i] += 1
            }
            for i in centers.indices where counts[i] > 0 {
                let n = Float(counts[i])
                centers[i] = RGB(r: sums[i].r / n, g: sums[i].g / n, b: sums[i].b / n)
            }
        }
        return centers
    }

    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
