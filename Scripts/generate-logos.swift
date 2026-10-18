#!/usr/bin/env swift
// Génère les propositions de logo de ConvertDock (PNG 1024 px) et une planche récapitulative.
// Usage : swift Scripts/generate-logos.swift <dossier-de-sortie>

import AppKit

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Logos", isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let canvas: CGFloat = 1024
// Grille d'icône macOS : contenu de 824 px, marge de 100 px, coin continu ~ 185 px.
let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let corner: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func squircle(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .semibold, colors: [NSColor]) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: colors))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
}

func drawSymbol(_ name: String, size: CGFloat, center: CGPoint, weight: NSFont.Weight = .semibold,
                colors: [NSColor] = [.white], shadow: Bool = true) {
    guard let image = symbol(name, size: size, weight: weight, colors: colors) else { return }
    NSGraphicsContext.saveGraphicsState()
    if shadow {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.25)
        s.shadowOffset = NSSize(width: 0, height: -10)
        s.shadowBlurRadius = 24
        s.set()
    }
    let r = CGRect(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2,
                   width: image.size.width, height: image.size.height)
    image.draw(in: r)
    NSGraphicsContext.restoreGraphicsState()
}

/// Fond de l'icône : dégradé, reflet supérieur et liseré lumineux (effet verre).
func base(_ colors: [NSColor], angle: CGFloat = -90) {
    let shape = squircle(iconRect, corner)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 30
    shadow.set()
    NSGradient(colors: colors)!.draw(in: shape, angle: angle)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // Reflet spéculaire en haut.
    let gloss = NSBezierPath(ovalIn: CGRect(x: iconRect.minX - 120, y: iconRect.midY + 40, width: iconRect.width + 240, height: 620))
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.32), NSColor.white.withAlphaComponent(0)])!.draw(in: gloss, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let rim = squircle(iconRect.insetBy(dx: 2, dy: 2), corner - 2)
    rim.lineWidth = 4
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.7), NSColor.white.withAlphaComponent(0.05), NSColor.white.withAlphaComponent(0.25)])!
        .draw(in: rim.strokedPath(), angle: -90)
}

/// Plaque de verre dépoli.
func glassPlate(_ path: NSBezierPath, tint: NSColor = .white, alpha: CGFloat = 0.2) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(0.22)
    s.shadowOffset = NSSize(width: 0, height: -16)
    s.shadowBlurRadius = 40
    s.set()
    tint.withAlphaComponent(alpha).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0.0)])!
        .draw(in: path.bounds, angle: -70)
    NSGraphicsContext.restoreGraphicsState()

    path.lineWidth = 3
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.85), NSColor.white.withAlphaComponent(0.15)])!
        .draw(in: path.strokedPath(), angle: -90)
}

extension NSBezierPath {
    func strokedPath() -> NSBezierPath {
        let cg = self.cgPath.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return NSBezierPath(cgPath: cg)
    }
}

struct Concept {
    let file: String
    let name: String
    let pitch: String
    let draw: () -> Void
}

let center = CGPoint(x: canvas / 2, y: canvas / 2)

let concepts: [Concept] = [
    Concept(file: "1-glass-loop", name: "Glass Loop", pitch: "Disque de verre et flèches de conversion — l'icône par défaut.") {
        base([color(0x3FA8FF), color(0x5B5BF7), color(0x7B2FF7)])
        glassPlate(NSBezierPath(ovalIn: CGRect(x: center.x - 270, y: center.y - 270, width: 540, height: 540)))
        drawSymbol("arrow.triangle.2.circlepath", size: 300, center: center, weight: .bold)
    },
    Concept(file: "2-drop-dock", name: "Drop Dock", pitch: "Un fichier qui tombe dans un plateau de verre : « déposer pour convertir ».") {
        base([color(0xFF7AB6), color(0xB04DFF), color(0x5A3BFF)])
        let tray = squircle(CGRect(x: 232, y: 230, width: 560, height: 210), 70)
        glassPlate(tray)
        drawSymbol("doc.fill", size: 300, center: CGPoint(x: center.x, y: center.y + 120), weight: .regular, colors: [.white])
        drawSymbol("arrow.down", size: 120, center: CGPoint(x: center.x, y: center.y + 100), weight: .heavy, colors: [color(0x8A3FFF)], shadow: false)
    },
    Concept(file: "3-prism", name: "Prism", pitch: "Un prisme de verre qui décompose un fichier en plusieurs formats.") {
        base([color(0x1B1F3B), color(0x0B0D1A)])
        let beams: [NSColor] = [color(0xFF4D6D), color(0xFFA62B), color(0xFFE14D), color(0x3DDC97), color(0x4DA8FF), color(0xA66CFF)]
        for (i, c) in beams.enumerated() {
            let p = NSBezierPath()
            let y0 = center.y - 10
            let spread = CGFloat(i) * 46 - 115
            p.move(to: CGPoint(x: center.x + 70, y: y0 + 10))
            p.line(to: CGPoint(x: iconRect.maxX + 10, y: y0 + spread * 2.1 + 28))
            p.line(to: CGPoint(x: iconRect.maxX + 10, y: y0 + spread * 2.1 - 28))
            p.close()
            NSGraphicsContext.saveGraphicsState()
            squircle(iconRect, corner).addClip()
            c.withAlphaComponent(0.85).setFill()
            p.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let beam = NSBezierPath()
        beam.move(to: CGPoint(x: iconRect.minX - 10, y: center.y - 70))
        beam.line(to: CGPoint(x: center.x - 60, y: center.y + 10))
        beam.lineWidth = 22
        NSGraphicsContext.saveGraphicsState()
        squircle(iconRect, corner).addClip()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        beam.lineCapStyle = .round
        beam.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let prism = NSBezierPath()
        prism.move(to: CGPoint(x: center.x, y: center.y + 230))
        prism.line(to: CGPoint(x: center.x - 220, y: center.y - 170))
        prism.line(to: CGPoint(x: center.x + 220, y: center.y - 170))
        prism.close()
        glassPlate(prism, alpha: 0.18)
    },
    Concept(file: "4-morph", name: "Morph", pitch: "Une photo qui se transforme en document : la conversion en une image.") {
        base([color(0x3EE6C1), color(0x14B8A6), color(0x0E7490)])
        let back = squircle(CGRect(x: 210, y: 330, width: 380, height: 430), 70)
        glassPlate(back, alpha: 0.22)
        drawSymbol("photo.fill", size: 150, center: CGPoint(x: 400, y: 545), weight: .medium, shadow: false)
        let front = squircle(CGRect(x: 440, y: 240, width: 380, height: 430), 70)
        glassPlate(front, alpha: 0.32)
        drawSymbol("text.alignleft", size: 150, center: CGPoint(x: 630, y: 455), weight: .bold, shadow: false)
        drawSymbol("arrow.right.circle.fill", size: 130, center: CGPoint(x: 512, y: 330), weight: .bold, colors: [.white, color(0x0E7490)])
    },
    Concept(file: "5-monogram", name: "Monogramme", pitch: "Les initiales CD gravées dans une bille de verre, sur un coucher de soleil.") {
        base([color(0xFFC94D), color(0xFF7A3D), color(0xF0386B)])
        glassPlate(NSBezierPath(ovalIn: CGRect(x: center.x - 290, y: center.y - 290, width: 580, height: 580)), alpha: 0.16)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 300, weight: .black).withRoundedDesign(),
            .foregroundColor: NSColor.white,
            .kern: -12,
        ]
        let text = NSAttributedString(string: "CD", attributes: attrs)
        let size = text.size()
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.25)
        s.shadowOffset = NSSize(width: 0, height: -10)
        s.shadowBlurRadius = 20
        s.set()
        text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2 + 6))
        NSGraphicsContext.restoreGraphicsState()
    },
    Concept(file: "6-stack", name: "Stack", pitch: "Trois cartes de verre — image, vidéo, texte — déployées en éventail.") {
        base([color(0x7DD3FC), color(0x3B82F6), color(0x1E3A8A)])
        let cards: [(String, CGFloat, CGFloat)] = [("waveform", -18, -170), ("photo.fill", 18, 170), ("film.fill", 0, 0)]
        for (name, angle, dx) in cards {
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.translateX(by: center.x + dx, yBy: center.y - abs(dx) * 0.3 + 20)
            t.rotate(byDegrees: -angle)
            t.concat()
            glassPlate(squircle(CGRect(x: -150, y: -200, width: 300, height: 400), 56), tint: dx == 0 ? .white : color(0x1E3A8A), alpha: dx == 0 ? 0.42 : 0.3)
            drawSymbol(name, size: 120, center: .zero, weight: .semibold, shadow: false)
            NSGraphicsContext.restoreGraphicsState()
        }
    },
]

extension NSFont {
    func withRoundedDesign() -> NSFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

func render(_ size: CGFloat, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    ctx.cgContext.scaleBy(x: size / canvas, y: size / canvas)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

for concept in concepts {
    try save(render(1024, concept.draw), outputDir.appendingPathComponent("\(concept.file).png"))
    print("✓ \(concept.name)")
}

// Planche récapitulative 3 × 2 avec légendes.
let tile: CGFloat = 520, labelHeight: CGFloat = 120, cols = 3
let rows = Int(ceil(Double(concepts.count) / Double(cols)))
let sheetSize = NSSize(width: tile * CGFloat(cols), height: (tile + labelHeight) * CGFloat(rows) + 140)
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sheetSize.width), pixelsHigh: Int(sheetSize.height),
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSGradient(colors: [color(0xF5F5F7), color(0xE4E6EE)])!.draw(in: CGRect(origin: .zero, size: sheetSize), angle: -90)
NSAttributedString(string: "ConvertDock — propositions de logo", attributes: [
    .font: NSFont.systemFont(ofSize: 44, weight: .bold), .foregroundColor: color(0x1D1D1F),
]).draw(at: CGPoint(x: 50, y: sheetSize.height - 95))
for (i, concept) in concepts.enumerated() {
    let col = i % cols, row = i / cols
    let x = CGFloat(col) * tile
    let y = sheetSize.height - 140 - CGFloat(row + 1) * (tile + labelHeight) + labelHeight
    let icon = render(1024, concept.draw)
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.addRepresentation(icon)
    image.draw(in: CGRect(x: x + 40, y: y, width: tile - 80, height: tile - 80))
    NSAttributedString(string: "\(i + 1). \(concept.name)", attributes: [
        .font: NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor: color(0x1D1D1F),
    ]).draw(at: CGPoint(x: x + 50, y: y - 40))
    NSAttributedString(string: concept.pitch, attributes: [
        .font: NSFont.systemFont(ofSize: 17), .foregroundColor: color(0x6E6E73),
    ]).draw(in: CGRect(x: x + 50, y: y - 110, width: tile - 100, height: 66))
}
NSGraphicsContext.restoreGraphicsState()
try save(sheet, outputDir.appendingPathComponent("0-planche.png"))
print("✓ Planche")
