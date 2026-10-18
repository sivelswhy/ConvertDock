import Foundation

/// YAML minimal sans dépendance : mappings et listes en bloc, scalaires (chaînes, nombres, booléens, null),
/// listes / objets en ligne simples (`[a, b]`, `{a: 1}`), commentaires et chaînes multilignes `|` / `>`.
enum YAML {
    // MARK: Écriture

    static func emit(_ value: Any) -> String {
        var lines: [String] = []
        write(value, indent: 0, into: &lines, inList: false)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func write(_ value: Any, indent: Int, into lines: inout [String], inList: Bool) {
        let pad = String(repeating: "  ", count: indent)
        if let dict = value as? [String: Any] {
            if dict.isEmpty { lines.append(pad + "{}"); return }
            for key in dict.keys.sorted() {
                let child = dict[key]!
                if isScalar(child) {
                    lines.append("\(pad)\(scalarKey(key)): \(scalar(child))")
                } else if isEmptyCollection(child) {
                    lines.append("\(pad)\(scalarKey(key)): \(child is [Any] ? "[]" : "{}")")
                } else {
                    lines.append("\(pad)\(scalarKey(key)):")
                    write(child, indent: child is [Any] ? indent : indent + 1, into: &lines, inList: false)
                }
            }
        } else if let array = value as? [Any] {
            if array.isEmpty { lines.append(pad + "[]"); return }
            for item in array {
                if isScalar(item) || isEmptyCollection(item) {
                    lines.append("\(pad)- \(isScalar(item) ? scalar(item) : (item is [Any] ? "[]" : "{}"))")
                } else {
                    var nested: [String] = []
                    write(item, indent: indent + 1, into: &nested, inList: true)
                    // Le premier élément partage la ligne du tiret.
                    if let first = nested.first {
                        lines.append("\(pad)- " + first.dropFirst((indent + 1) * 2))
                        lines.append(contentsOf: nested.dropFirst())
                    }
                }
            }
        } else {
            lines.append(pad + scalar(value))
        }
    }

    private static func isScalar(_ value: Any) -> Bool { !(value is [Any]) && !(value is [String: Any]) }

    private static func isEmptyCollection(_ value: Any) -> Bool {
        (value as? [Any])?.isEmpty == true || (value as? [String: Any])?.isEmpty == true
    }

    private static func scalarKey(_ key: String) -> String { needsQuotes(key) ? quoted(key) : key }

    private static func scalar(_ value: Any) -> String {
        switch value {
        case is NSNull: return "null"
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        case let string as String:
            if string.contains("\n") {
                return "|\n" + string.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n")
            }
            return needsQuotes(string) ? quoted(string) : string
        default: return quoted("\(value)")
        }
    }

    private static func needsQuotes(_ s: String) -> Bool {
        if s.isEmpty { return true }
        if ["true", "false", "null", "yes", "no", "on", "off", "~"].contains(s.lowercased()) { return true }
        if Double(s) != nil { return true }
        if let first = s.first, "-?:,[]{}#&*!|>'\"%@`".contains(first) { return true }
        return s.contains(": ") || s.contains(" #") || s.hasSuffix(":") || s.first == " " || s.last == " "
    }

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: Lecture

    private struct Line {
        let indent: Int
        let text: String
    }

    static func parse(_ text: String) throws -> Any {
        var lines: [Line] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "---" || trimmed == "..." {
                // Les lignes vides comptent dans les blocs multilignes : on les garde marquées.
                lines.append(Line(indent: -1, text: ""))
                continue
            }
            let indent = raw.prefix { $0 == " " }.count
            lines.append(Line(indent: indent, text: stripComment(String(raw.dropFirst(indent)))))
        }
        var index = 0
        skipBlank(lines, &index)
        guard index < lines.count else { return NSNull() }
        return try parseBlock(lines, &index, indent: lines[index].indent)
    }

    private static func skipBlank(_ lines: [Line], _ i: inout Int) {
        while i < lines.count, lines[i].indent < 0 { i += 1 }
    }

    private static func parseBlock(_ lines: [Line], _ i: inout Int, indent: Int) throws -> Any {
        skipBlank(lines, &i)
        guard i < lines.count else { return NSNull() }
        if lines[i].text.hasPrefix("- ") || lines[i].text == "-" {
            var array: [Any] = []
            while i < lines.count {
                skipBlank(lines, &i)
                guard i < lines.count, lines[i].indent == indent, lines[i].text.hasPrefix("-") else { break }
                let rest = String(lines[i].text.dropFirst()).trimmingCharacters(in: .whitespaces)
                if rest.isEmpty {
                    i += 1
                    skipBlank(lines, &i)
                    array.append(i < lines.count && lines[i].indent > indent ? try parseBlock(lines, &i, indent: lines[i].indent) : NSNull())
                } else if keyValue(rest) != nil {
                    // « - clé: valeur » : objet dont la première clé est sur la ligne du tiret.
                    let childIndent = indent + (lines[i].text.count - rest.count)
                    var patched = lines
                    patched[i] = Line(indent: childIndent, text: rest)
                    array.append(try parseBlock(patched, &i, indent: childIndent))
                } else {
                    array.append(parseScalar(rest))
                    i += 1
                }
            }
            return array
        }

        var dict: [String: Any] = [:]
        while i < lines.count {
            skipBlank(lines, &i)
            guard i < lines.count, lines[i].indent == indent, let (key, value) = keyValue(lines[i].text) else { break }
            i += 1
            if value.isEmpty {
                skipBlank(lines, &i)
                if i < lines.count, lines[i].indent > indent || (lines[i].indent == indent && lines[i].text.hasPrefix("- ")) {
                    dict[key] = try parseBlock(lines, &i, indent: lines[i].indent)
                } else {
                    dict[key] = NSNull()
                }
            } else if value == "|" || value == ">" || value.hasPrefix("|") || value.hasPrefix(">") {
                var block: [String] = []
                var blockIndent: Int?
                while i < lines.count, lines[i].indent < 0 || lines[i].indent > indent {
                    if lines[i].indent < 0 { block.append("") } else {
                        blockIndent = blockIndent ?? lines[i].indent
                        block.append(String(repeating: " ", count: max(0, lines[i].indent - blockIndent!)) + lines[i].text)
                    }
                    i += 1
                }
                while block.last == "" { block.removeLast() }
                dict[key] = value.hasPrefix("|") ? block.joined(separator: "\n") : block.joined(separator: " ")
            } else {
                dict[key] = parseScalar(value)
            }
        }
        if dict.isEmpty, i < lines.count {
            throw ToolError.failed(L("Invalid YAML near line %d.", i + 1))
        }
        return dict
    }

    private static func keyValue(_ text: String) -> (String, String)? {
        var inQuote: Character?
        for (offset, char) in text.enumerated() {
            if let q = inQuote { if char == q { inQuote = nil }; continue }
            if char == "\"" || char == "'" { inQuote = char; continue }
            if char == ":" {
                let next = text.index(text.startIndex, offsetBy: offset + 1)
                if next == text.endIndex || text[next] == " " {
                    let key = String(text.prefix(offset)).trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty, !key.hasPrefix("[") , !key.hasPrefix("{") else { return nil }
                    return (unquote(key), String(text[next...]).trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return nil
    }

    private static func stripComment(_ text: String) -> String {
        var inQuote: Character?
        var previous: Character = " "
        for (offset, char) in text.enumerated() {
            if let q = inQuote { if char == q { inQuote = nil } }
            else if char == "\"" || char == "'" { inQuote = char }
            else if char == "#", previous == " " { return String(text.prefix(offset)).trimmingCharacters(in: .whitespaces) }
            previous = char
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func unquote(_ s: String) -> String {
        if s.count >= 2, let f = s.first, f == s.last, f == "\"" || f == "'" {
            let inner = String(s.dropFirst().dropLast())
            return f == "\"" ? inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\\", with: "\\")
                             : inner.replacingOccurrences(of: "''", with: "'")
        }
        return s
    }

    static func parseScalar(_ raw: String) -> Any {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("[") && s.hasSuffix("]") {
            return splitFlow(String(s.dropFirst().dropLast())).map(parseScalar)
        }
        if s.hasPrefix("{") && s.hasSuffix("}") {
            var dict: [String: Any] = [:]
            for item in splitFlow(String(s.dropFirst().dropLast())) {
                if let (k, v) = keyValue(item) { dict[k] = parseScalar(v) }
            }
            return dict
        }
        if let f = s.first, f == "\"" || f == "'" { return unquote(s) }
        switch s.lowercased() {
        case "null", "~", "": return NSNull()
        case "true", "yes", "on": return true
        case "false", "no", "off": return false
        default: break
        }
        if let int = Int(s) { return int }
        if let double = Double(s), s.rangeOfCharacter(from: .letters) == nil { return double }
        return s
    }

    private static func splitFlow(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inQuote: Character?
        for char in s {
            if let q = inQuote { current.append(char); if char == q { inQuote = nil }; continue }
            switch char {
            case "\"", "'": inQuote = char; current.append(char)
            case "[", "{": depth += 1; current.append(char)
            case "]", "}": depth -= 1; current.append(char)
            case "," where depth == 0: parts.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            default: current.append(char)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { parts.append(last) }
        return parts
    }
}
