import Foundation
import UniformTypeIdentifiers

enum DataTools {
    static var all: [Tool] {
        [
            Tool(id: "data.json.to.plist", title: "JSON → Property List", subtitle: "XML plist", symbol: "list.bullet.indent",
                 category: .data, inputs: [.json], keywords: ["json", "plist", "xml", "apple"]) { inputs, ctx in
                try inputs.map { url in
                    let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url), options: [.fragmentsAllowed])
                    let data = try PropertyListSerialization.data(fromPropertyList: stripNulls(object), format: .xml, options: 0)
                    let out = ctx.output(for: url, ext: "plist")
                    try data.write(to: out)
                    return out
                }
            },
            Tool(id: "data.plist.to.json", title: "Property List → JSON", subtitle: "XML or binary", symbol: "curlybraces",
                 category: .data, inputs: [.propertyList], keywords: ["plist", "json"]) { inputs, ctx in
                try inputs.map { url in
                    let object = try PropertyListSerialization.propertyList(from: try Data(contentsOf: url), format: nil)
                    let data = try JSONSerialization.data(withJSONObject: jsonSafe(object), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    let out = ctx.output(for: url, ext: "json")
                    try data.write(to: out)
                    return out
                }
            },
            Tool(id: "data.json.pretty", title: "Format JSON", subtitle: "Indented and sorted", symbol: "text.alignleft",
                 category: .data, inputs: [.json], keywords: ["json", "pretty", "formater", "indenter", "beautify"]) { inputs, ctx in
                try inputs.map { url in
                    let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url), options: [.fragmentsAllowed])
                    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
                    let out = ctx.output(for: url, ext: "json", suffix: L("formatted"))
                    try data.write(to: out)
                    return out
                }
            },
            Tool(id: "data.json.minify", title: "Minify JSON", subtitle: "No whitespace", symbol: "arrow.down.right.and.arrow.up.left",
                 category: .data, inputs: [.json], keywords: ["json", "minify", "minifier", "compacter"]) { inputs, ctx in
                try inputs.map { url in
                    let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url), options: [.fragmentsAllowed])
                    let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes, .fragmentsAllowed])
                    let out = ctx.output(for: url, ext: "json", suffix: "min")
                    try data.write(to: out)
                    return out
                }
            },
            Tool(id: "data.csv.to.json", title: "CSV → JSON", subtitle: "Array of objects", symbol: "tablecells",
                 category: .data, inputs: [.commaSeparatedText, .tabSeparatedText], keywords: ["csv", "json", "tableur", "excel"]) { inputs, ctx in
                try inputs.map { url in
                    let rows = CSV.parse(try String(contentsOf: url, encoding: .utf8), separator: url.pathExtension.lowercased() == "tsv" ? "\t" : nil)
                    guard let header = rows.first else { throw ToolError.failed(L("Empty CSV.")) }
                    let objects = rows.dropFirst().map { row in
                        Dictionary(header.enumerated().map { ($0.element, $0.offset < row.count ? row[$0.offset] : "") }, uniquingKeysWith: { a, _ in a })
                    }
                    let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .withoutEscapingSlashes])
                    let out = ctx.output(for: url, ext: "json")
                    try data.write(to: out)
                    return out
                }
            },
            Tool(id: "data.json.to.csv", title: "JSON → CSV", subtitle: "For Excel / Numbers", symbol: "tablecells.badge.ellipsis",
                 category: .data, inputs: [.json], keywords: ["json", "csv", "tableur", "excel", "numbers"]) { inputs, ctx in
                try inputs.map { url in
                    let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
                    guard let array = object as? [[String: Any]] else {
                        throw ToolError.unsupported(L("The JSON must be an array of objects."))
                    }
                    var keys: [String] = []
                    for item in array { for key in item.keys.sorted() where !keys.contains(key) { keys.append(key) } }
                    var lines = [keys.map(CSV.escape).joined(separator: ",")]
                    for item in array {
                        lines.append(keys.map { key in
                            guard let value = item[key], !(value is NSNull) else { return "" }
                            if JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) {
                                return CSV.escape(String(decoding: data, as: UTF8.self))
                            }
                            return CSV.escape("\(value)")
                        }.joined(separator: ","))
                    }
                    let out = ctx.output(for: url, ext: "csv")
                    try lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "data.json.to.yaml", title: "JSON → YAML", subtitle: "Readable configuration", symbol: "list.bullet.indent",
                 category: .data, inputs: [.json], keywords: ["json", "yaml", "yml", "config", "docker", "kubernetes"]) { inputs, ctx in
                try inputs.map { url in
                    let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url), options: [.fragmentsAllowed])
                    let out = ctx.output(for: url, ext: "yaml")
                    try YAML.emit(object).write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "data.yaml.to.json", title: "YAML → JSON", subtitle: "For APIs and scripts", symbol: "curlybraces",
                 category: .data, inputs: [.yaml], inputExtensions: ["yaml", "yml"],
                 keywords: ["yaml", "yml", "json", "config"]) { inputs, ctx in
                try inputs.map { url in
                    let object = try YAML.parse(try String(contentsOf: url, encoding: .utf8))
                    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed])
                    let out = ctx.output(for: url, ext: "json")
                    try data.write(to: out)
                    return out
                }
            },
            Tool(id: "data.csv.to.html", title: "CSV → HTML table", subtitle: "Styled table, ready to share", symbol: "tablecells",
                 category: .data, inputs: [.commaSeparatedText, .tabSeparatedText], keywords: ["csv", "html", "tableau", "table", "web"]) { inputs, ctx in
                try inputs.map { url in
                    let rows = CSV.parse(try String(contentsOf: url, encoding: .utf8), separator: url.pathExtension.lowercased() == "tsv" ? "\t" : nil)
                    guard let header = rows.first else { throw ToolError.failed(L("Empty CSV.")) }
                    let cell = { (tag: String, value: String) in "<\(tag)>\(Markdown.escape(value))</\(tag)>" }
                    let body = rows.dropFirst().map { "<tr>" + $0.map { cell("td", $0) }.joined() + "</tr>" }.joined(separator: "\n")
                    let html = """
                    <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(Markdown.escape(url.baseName))</title>
                    <style>body{font-family:-apple-system,sans-serif;margin:2em}table{border-collapse:collapse}th,td{border:1px solid #d1d1d6;padding:.4em .7em;text-align:left}th{background:#f2f2f7}tr:nth-child(even) td{background:#fafafa}</style>
                    </head><body><table>
                    <thead><tr>\(header.map { cell("th", $0) }.joined())</tr></thead>
                    <tbody>
                    \(body)
                    </tbody></table></body></html>
                    """
                    let out = ctx.output(for: url, ext: "html")
                    try html.write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "data.csv.to.md", title: "CSV → Markdown table", subtitle: "For READMEs and notes", symbol: "tablecells",
                 category: .data, inputs: [.commaSeparatedText, .tabSeparatedText], keywords: ["csv", "markdown", "md", "tableau", "table", "github"]) { inputs, ctx in
                try inputs.map { url in
                    let rows = CSV.parse(try String(contentsOf: url, encoding: .utf8), separator: url.pathExtension.lowercased() == "tsv" ? "\t" : nil)
                    guard let header = rows.first else { throw ToolError.failed(L("Empty CSV.")) }
                    let clean = { (v: String) in v.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
                    var lines = ["| " + header.map(clean).joined(separator: " | ") + " |", "|" + header.map { _ in " --- " }.joined(separator: "|") + "|"]
                    for row in rows.dropFirst() {
                        let padded = (0..<header.count).map { $0 < row.count ? clean(row[$0]) : "" }
                        lines.append("| " + padded.joined(separator: " | ") + " |")
                    }
                    let out = ctx.output(for: url, ext: "md")
                    try (lines.joined(separator: "\n") + "\n").write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            plistFormat(id: "data.plist.binary", title: "Convert plist to binary", subtitle: "Compact, read faster", format: .binary, suffix: L("binary")),
            plistFormat(id: "data.plist.xml", title: "Convert plist to XML", subtitle: "Readable and editable", format: .xml, suffix: "XML"),
            Tool(id: "data.base64", title: "Encode to Base64", subtitle: "Any file → text", symbol: "number.square",
                 category: .data, inputs: [.data], keywords: ["base64", "encoder", "data uri"]) { inputs, ctx in
                try inputs.map { url in
                    let out = ctx.output(for: url, ext: "txt", suffix: "base64")
                    try Data(contentsOf: url).base64EncodedString().write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "data.checksum", title: "Compute SHA-256 checksum", subtitle: "Verify integrity", symbol: "checkmark.shield",
                 category: .data, inputs: [.data], keywords: ["hash", "sha256", "checksum", "empreinte", "md5", "intégrité"]) { inputs, ctx in
                try inputs.map { url in
                    let result = try Shell.run("/usr/bin/shasum", ["-a", "256", url.path])
                    let out = ctx.output(for: url, ext: "sha256")
                    try result.write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "data.checksum.md5", title: "Compute MD5 checksum", subtitle: "Classic fingerprint, for downloads",
                 symbol: "checkmark.shield", category: .data, inputs: [.data], keywords: ["hash", "md5", "checksum", "empreinte", "intégrité"]) { inputs, ctx in
                try inputs.map { url in
                    let out = ctx.output(for: url, ext: "md5")
                    try Shell.run("/sbin/md5", ["-r", url.path]).write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "data.hexdump", title: "Hex dump", subtitle: "Raw bytes, readable → .txt",
                 symbol: "number.square", category: .data, inputs: [.data], keywords: ["hex", "hexadécimal", "xxd", "octets", "binaire", "dump"]) { inputs, ctx in
                try inputs.map { url in
                    let out = ctx.output(for: url, ext: "txt", suffix: "hex")
                    try Shell.run("/usr/bin/xxd", [url.path]).write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "data.xml.to.json", title: "XML → JSON", subtitle: "Attributes as @name, text as #text", symbol: "curlybraces",
                 category: .data, inputs: [.xml], keywords: ["xml", "json", "convertir", "rss", "svg"]) { inputs, ctx in
                try inputs.map { url in
                    let object = try XMLToJSON.convert(try Data(contentsOf: url))
                    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    let out = ctx.output(for: url, ext: "json")
                    try data.write(to: out)
                    return out
                }
            },
            Tool(id: "data.csv.to.tsv", title: "CSV → TSV", subtitle: "Tab-separated", symbol: "tablecells",
                 category: .data, inputs: [.commaSeparatedText], excludes: [.tabSeparatedText], keywords: ["csv", "tsv", "tabulation", "tab"]) { inputs, ctx in
                try inputs.map { url in
                    let rows = CSV.parse(try String(contentsOf: url, encoding: .utf8))
                    let clean = { (v: String) in v.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
                    let out = ctx.output(for: url, ext: "tsv")
                    try (rows.map { $0.map(clean).joined(separator: "\t") }.joined(separator: "\n") + "\n").write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "data.tsv.to.csv", title: "TSV → CSV", subtitle: "Comma-separated", symbol: "tablecells",
                 category: .data, inputs: [.tabSeparatedText], keywords: ["tsv", "csv", "tabulation", "excel"]) { inputs, ctx in
                try inputs.map { url in
                    let rows = CSV.parse(try String(contentsOf: url, encoding: .utf8), separator: "\t")
                    let out = ctx.output(for: url, ext: "csv")
                    try (rows.map { $0.map(CSV.escape).joined(separator: ",") }.joined(separator: "\n") + "\n").write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "data.xlsx.to.csv", title: "Excel (XLSX) → CSV", subtitle: "One CSV per sheet", symbol: "tablecells",
                 category: .data, inputs: [.xlsx], inputExtensions: ["xlsx"], keywords: ["excel", "xlsx", "csv", "tableur", "numbers", "feuille"]) { inputs, ctx in
                try inputs.map { url in
                    let sheets = try XLSX.sheets(url)
                    guard !sheets.isEmpty else { throw ToolError.failed(L("Empty CSV.")) }
                    let csv = { (rows: [[String]]) in rows.map { $0.map(CSV.escape).joined(separator: ",") }.joined(separator: "\n") + "\n" }
                    if sheets.count == 1 {
                        let out = ctx.output(for: url, ext: "csv")
                        try csv(sheets[0].rows).write(to: out, atomically: true, encoding: .utf8)
                        return out
                    }
                    let folder = try PDFTools.makeFolder(for: url, name: "CSV")
                    for sheet in sheets {
                        let name = sheet.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                        try csv(sheet.rows).write(to: folder.appendingPathComponent(name + ".csv"), atomically: true, encoding: .utf8)
                    }
                    return folder
                }
            },
            Tool(id: "data.sqlite.to.csv", title: "SQLite database → CSV", subtitle: "One CSV per table", symbol: "cylinder.split.1x2",
                 category: .data, inputs: [], inputExtensions: ["sqlite", "sqlite3", "db"],
                 keywords: ["sqlite", "base de données", "database", "db", "csv", "tables", "export"]) { inputs, ctx in
                try inputs.map { url in
                    let names = try Shell.run("/usr/bin/sqlite3", ["-readonly", url.path,
                        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"])
                        .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                    guard !names.isEmpty else { throw ToolError.failed(L("No tables in this database.")) }
                    let folder = try PDFTools.makeFolder(for: url, name: "CSV")
                    for name in names {
                        let quoted = "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                        let csv = try Shell.run("/usr/bin/sqlite3", ["-readonly", "-csv", "-header", url.path, "SELECT * FROM \(quoted)"])
                        try csv.write(to: folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-") + ".csv"), atomically: true, encoding: .utf8)
                    }
                    return folder
                }
            },
        ]
    }

    private static func plistFormat(id: String, title: String, subtitle: String, format: PropertyListSerialization.PropertyListFormat, suffix: String) -> Tool {
        Tool(id: id, title: title, subtitle: subtitle, symbol: "list.bullet.rectangle", category: .data, inputs: [.propertyList],
             keywords: ["plist", "binaire", "binary", "xml", "apple", "préférences"]) { inputs, ctx in
            try inputs.map { url in
                let object = try PropertyListSerialization.propertyList(from: try Data(contentsOf: url), format: nil)
                let data = try PropertyListSerialization.data(fromPropertyList: object, format: format, options: 0)
                let out = ctx.output(for: url, ext: "plist", suffix: suffix)
                try data.write(to: out)
                return out
            }
        }
    }

    private static func stripNulls(_ value: Any) -> Any {
        if let dict = value as? [String: Any] { return dict.filter { !($0.value is NSNull) }.mapValues(stripNulls) }
        if let array = value as? [Any] { return array.filter { !($0 is NSNull) }.map(stripNulls) }
        return value
    }

    private static func jsonSafe(_ value: Any) -> Any {
        if let dict = value as? [String: Any] { return dict.mapValues(jsonSafe) }
        if let array = value as? [Any] { return array.map(jsonSafe) }
        if let date = value as? Date { return ISO8601DateFormatter().string(from: date) }
        if let data = value as? Data { return data.base64EncodedString() }
        return value
    }
}

enum CSV {
    /// Analyse RFC 4180 (guillemets, retours à la ligne dans les champs). Détecte « , » ou « ; ».
    static func parse(_ text: String, separator: Character? = nil) -> [[String]] {
        let firstLine = text.prefix { $0 != "\n" }
        let sep = separator ?? (firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ",")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        while let c = iterator.next() {
            if quoted {
                if c == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else {
                            quoted = false
                            if next == sep { row.append(field); field = "" }
                            else if next == "\n" || next == "\r\n" { row.append(field); rows.append(row); row = []; field = "" }
                            else if next != "\r" { field.append(next) }
                        }
                    } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" && field.isEmpty {
                quoted = true
            } else if c == sep {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" {
                row.append(field); rows.append(row); row = []; field = ""
            } else if c != "\r" {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func escape(_ value: String) -> String {
        value.contains(where: { ",\"\n;".contains($0) }) ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" : value
    }
}

enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // Pas d'entrée : un outil qui demanderait une saisie (mot de passe…) échoue au lieu de bloquer.
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe(), errors = Pipe()
        process.standardOutput = pipe
        process.standardError = errors
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ToolError.failed(String(decoding: errorOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: output, as: UTF8.self)
    }
}

/// XML → objets JSON : chaque élément devient un dictionnaire (attributs « @nom », texte « #text »),
/// les enfants répétés deviennent des tableaux, un élément ne contenant que du texte devient une chaîne.
final class XMLToJSON: NSObject, XMLParserDelegate {
    private var stack: [(name: String, object: [String: Any], text: String)] = [("", [:], "")]

    static func convert(_ data: Data) throws -> Any {
        let parser = XMLParser(data: data)
        let delegate = XMLToJSON()
        parser.delegate = delegate
        guard parser.parse() else {
            throw ToolError.failed(parser.parserError?.localizedDescription ?? L("Invalid XML."))
        }
        return delegate.stack[0].object
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        stack.append((name, Dictionary(uniqueKeysWithValues: attributes.map { ("@" + $0.key, $0.value as Any) }), ""))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { stack[stack.count - 1].text += string }
    func parser(_ parser: XMLParser, foundCDATA block: Data) { stack[stack.count - 1].text += String(decoding: block, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let element = stack.removeLast()
        let text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var value: Any = element.object
        if element.object.isEmpty { value = text } else if !text.isEmpty { var o = element.object; o["#text"] = text; value = o }
        var parent = stack[stack.count - 1].object
        if let existing = parent[name] {
            parent[name] = (existing as? [Any] ?? [existing]) + [value]
        } else {
            parent[name] = value
        }
        stack[stack.count - 1].object = parent
    }
}

/// Lecture minimale d'un classeur Excel : un .xlsx est un ZIP de fichiers XML.
/// shortcut: les dates restent des numéros de série Excel et les formules donnent leur dernière valeur calculée.
enum XLSX {
    struct Sheet { let name: String; let rows: [[String]] }

    static func sheets(_ url: URL) throws -> [Sheet] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, folder.path])
        defer { try? FileManager.default.removeItem(at: folder) }
        let xl = folder.appendingPathComponent("xl")
        var shared: [String] = []
        if let data = try? Data(contentsOf: xl.appendingPathComponent("sharedStrings.xml")) {
            let reader = Reader(shared: [])
            _ = reader.parse(data)
            shared = reader.strings
        }
        // Ordre et noms des feuilles : workbook.xml → relations → fichiers.
        let rels = try Reader.attributes(of: "Relationship", in: Data(contentsOf: xl.appendingPathComponent("_rels/workbook.xml.rels")))
        let targets = Dictionary(rels.compactMap { a in a["Id"].flatMap { id in a["Target"].map { (id, $0) } } }, uniquingKeysWith: { a, _ in a })
        return try Reader.attributes(of: "sheet", in: Data(contentsOf: xl.appendingPathComponent("workbook.xml"))).compactMap { sheet in
            guard let id = sheet["r:id"], var target = targets[id] else { return nil }
            target = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(target)) else { return nil }
            let reader = Reader(shared: shared)
            return Sheet(name: sheet["name"] ?? "Sheet", rows: reader.parse(data))
        }
    }

    private final class Reader: NSObject, XMLParserDelegate {
        let shared: [String]
        var strings: [String] = []
        private var grid: [Int: [Int: String]] = [:]
        private var row = 0, column = 0, cellType = "", text = "", inValue = false, inString = false
        private var collected: [[String: String]] = []
        private var wanted = ""

        init(shared: [String]) { self.shared = shared }

        static func attributes(of element: String, in data: Data) -> [[String: String]] {
            let reader = Reader(shared: [])
            reader.wanted = element
            let parser = XMLParser(data: data)
            parser.delegate = reader
            parser.parse()
            return reader.collected
        }

        func parse(_ data: Data) -> [[String]] {
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.parse()
            guard let lastRow = grid.keys.max(), lastRow >= 1 else { return [] }
            let width = (grid.values.compactMap { $0.keys.max() }.max() ?? 0) + 1
            return (1...lastRow).map { r in (0..<width).map { grid[r]?[$0] ?? "" } }
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == wanted { collected.append(attributes) }
            switch name {
            case "si": text = ""; inString = true
            case "row": row = Int(attributes["r"] ?? "") ?? row + 1; column = -1
            case "c":
                let ref = attributes["r"] ?? ""
                let letters = ref.prefix { $0.isLetter }.uppercased()
                column = letters.isEmpty ? column + 1 : letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
                cellType = attributes["t"] ?? ""
                text = ""
            case "v", "t": inValue = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { if inValue { text += string } }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "v", "t": inValue = false
            case "si": strings.append(text); inString = false
            case "c" where !inString:
                var value = text
                if cellType == "s", let index = Int(text), index < shared.count { value = shared[index] }
                if cellType == "b" { value = text == "1" ? "TRUE" : "FALSE" }
                if !value.isEmpty { grid[row, default: [:]][column] = value }
            default: break
            }
        }
    }
}
