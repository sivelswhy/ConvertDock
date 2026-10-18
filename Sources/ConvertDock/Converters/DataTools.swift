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
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
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
