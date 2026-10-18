import ModelIO
import UniformTypeIdentifiers

/// Modèles 3D via Model I/O : OBJ, STL, PLY, USD/USDZ, Alembic.
enum ModelTools {
    static let extensions = ["obj", "stl", "ply", "usd", "usda", "usdc", "usdz", "abc"]

    private struct Target {
        let ext: String
        let name: String
        let subtitle: String
        let keywords: [String]
    }

    private static let targets: [Target] = [
        Target(ext: "usdz", name: "USDZ", subtitle: "AR Quick Look on iPhone and Vision Pro", keywords: ["ar", "réalité augmentée", "augmented reality", "iphone", "vision pro", "quick look"]),
        Target(ext: "obj", name: "OBJ", subtitle: "Universal format for 3D software", keywords: ["wavefront", "blender"]),
        Target(ext: "stl", name: "STL", subtitle: "For 3D printing", keywords: ["impression 3d", "3d printing", "slicer", "cura", "prusa"]),
        Target(ext: "ply", name: "PLY", subtitle: "Polygons and point clouds", keywords: ["nuage de points", "point cloud", "scan"]),
        Target(ext: "usdc", name: "USD", subtitle: "Universal Scene Description", keywords: ["pixar", "usd"]),
    ]

    static var all: [Tool] {
        targets.filter { $0.ext == "usdz" || MDLAsset.canExportFileExtension($0.ext) }.map { target in
            Tool(id: "3d.to.\(target.ext)", title: "Convert to \(target.name)", subtitle: target.subtitle,
                 symbol: "cube.transparent", category: .model, inputs: [],
                 inputExtensions: extensions.filter { $0 != target.ext },
                 keywords: ["3d", "modèle", "model", "convertir", target.ext] + target.keywords) { inputs, ctx in
                try inputs.map { url in
                    guard MDLAsset.canImportFileExtension(url.pathExtension.lowercased()) else {
                        throw ToolError.unsupported(L("This 3D format cannot be read."))
                    }
                    let asset = MDLAsset(url: url)
                    guard asset.count > 0 else { throw ToolError.unreadable(url) }
                    let out = ctx.output(for: url, ext: target.ext)
                    if target.ext == "usdz" && !MDLAsset.canExportFileExtension("usdz") {
                        try exportUSDZ(asset, to: out)
                    } else {
                        try asset.export(to: out)
                    }
                    return out
                }
            }
        }
    }

    /// Model I/O ne sait pas écrire l'USDZ : on exporte en USDC puis on l'empaquette.
    /// Un USDZ est une archive ZIP sans compression dont les données sont alignées sur 64 octets.
    static func exportUSDZ(_ asset: MDLAsset, to out: URL) throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("usdc")
        defer { try? fm.removeItem(at: tmp) }
        try asset.export(to: tmp)
        try writeStoredZip(entries: [(out.deletingPathExtension().lastPathComponent + ".usdc", try Data(contentsOf: tmp))], to: out)
    }

    static func writeStoredZip(entries: [(name: String, data: Data)], to out: URL) throws {
        var archive = Data()
        var central = Data()
        func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(truncatingIfNeeded: v).littleEndian) { Data($0) } }
        func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(truncatingIfNeeded: v).littleEndian) { Data($0) } }

        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = Int(CRC32.checksum(entry.data))
            let offset = archive.count
            // Champ « extra » de bourrage pour aligner le début des données sur 64 octets.
            let base = offset + 30 + name.count + 4
            let padding = (64 - base % 64) % 64
            let extra = le16(0x1986) + le16(padding) + Data(count: padding)
            archive += le32(0x0403_4B50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0x21)
            archive += le32(crc) + le32(entry.data.count) + le32(entry.data.count) + le16(name.count) + le16(extra.count)
            archive += name + extra + entry.data

            central += le32(0x0201_4B50) + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0x21)
            central += le32(crc) + le32(entry.data.count) + le32(entry.data.count) + le16(name.count)
            central += le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + name
        }
        let centralOffset = archive.count
        archive += central
        archive += le32(0x0605_4B50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count)
        archive += le32(central.count) + le32(centralOffset) + le16(0)
        try archive.write(to: out)
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}
