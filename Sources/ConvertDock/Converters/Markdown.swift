import Foundation

/// Convertisseur Markdown → HTML minimaliste (titres, listes, citations, code, liens, emphase, tableaux simples).
enum Markdown {
    static func html(from markdown: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="fr"><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>
        body { font-family: -apple-system, "Helvetica Neue", sans-serif; font-size: 13pt; line-height: 1.55; color: #1d1d1f; max-width: 46em; margin: 2em auto; padding: 0 1em; }
        h1, h2, h3, h4 { line-height: 1.2; margin: 1.2em 0 .5em; }
        code { font-family: Menlo, monospace; font-size: .9em; background: #f2f2f5; padding: .1em .3em; border-radius: 4px; }
        pre { background: #f2f2f5; padding: .8em 1em; border-radius: 8px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { border-left: 3px solid #c7c7cc; margin: 0; padding-left: 1em; color: #555; }
        table { border-collapse: collapse; } td, th { border: 1px solid #d1d1d6; padding: .3em .6em; }
        img { max-width: 100%; }
        </style></head><body>
        \(body(from: markdown))
        </body></html>
        """
    }

    static func body(from markdown: String) -> String {
        var html: [String] = []
        var paragraph: [String] = []
        var listStack: [String] = []
        var inCode = false
        var codeLines: [String] = []
        var tableRows: [[String]] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                html.append("<p>\(inline(paragraph.joined(separator: " ")))</p>")
                paragraph.removeAll()
            }
        }
        func closeLists() {
            while let tag = listStack.popLast() { html.append("</\(tag)>") }
        }
        func flushTable() {
            guard !tableRows.isEmpty else { return }
            var out = "<table>"
            for (i, row) in tableRows.enumerated() {
                let tag = i == 0 ? "th" : "td"
                out += "<tr>" + row.map { "<\(tag)>\(inline($0))</\(tag)>" }.joined() + "</tr>"
            }
            html.append(out + "</table>")
            tableRows.removeAll()
        }
        func flushAll() { flushParagraph(); closeLists(); flushTable() }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    html.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flushAll()
                    inCode = true
                }
                continue
            }
            if inCode { codeLines.append(rawLine); continue }

            if line.isEmpty { flushAll(); continue }

            if line.hasPrefix("|") && line.hasSuffix("|") {
                flushParagraph(); closeLists()
                let cells = line.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { tableRows.append(cells) }
                continue
            }
            flushTable()

            if let level = headingLevel(line) {
                flushParagraph(); closeLists()
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                html.append("<h\(level)>\(inline(text))</h\(level)>")
            } else if ["---", "***", "___"].contains(line) {
                flushParagraph(); closeLists()
                html.append("<hr>")
            } else if line.hasPrefix(">") {
                flushParagraph(); closeLists()
                html.append("<blockquote>\(inline(line.dropFirst().trimmingCharacters(in: .whitespaces)))</blockquote>")
            } else if let item = listItem(line) {
                flushParagraph()
                if listStack.last != item.tag {
                    closeLists()
                    html.append("<\(item.tag)>")
                    listStack.append(item.tag)
                }
                html.append("<li>\(inline(item.text))</li>")
            } else {
                closeLists()
                paragraph.append(line)
            }
        }
        if inCode { html.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>") }
        flushAll()
        return html.joined(separator: "\n")
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func listItem(_ line: String) -> (tag: String, text: String)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            var text = String(line.dropFirst(2))
            if text.hasPrefix("[ ] ") { text = "☐ " + text.dropFirst(4) }
            if text.lowercased().hasPrefix("[x] ") { text = "☑ " + text.dropFirst(4) }
            return ("ul", text)
        }
        if let match = line.firstMatch(of: #/^\d+[.)]\s+(.*)$/#) {
            return ("ol", String(match.1))
        }
        return nil
    }

    static func inline(_ text: String) -> String {
        var s = escape(text)
        s = s.replacing(#/`([^`]+)`/#) { "<code>\($0.1)</code>" }
        s = s.replacing(#/!\[([^\]]*)\]\(([^)\s]+)\)/#) { "<img alt=\"\($0.1)\" src=\"\($0.2)\">" }
        s = s.replacing(#/\[([^\]]+)\]\(([^)\s]+)\)/#) { "<a href=\"\($0.2)\">\($0.1)</a>" }
        s = s.replacing(#/\*\*([^*]+)\*\*/#) { "<strong>\($0.1)</strong>" }
        s = s.replacing(#/__([^_]+)__/#) { "<strong>\($0.1)</strong>" }
        s = s.replacing(#/\*([^*]+)\*/#) { "<em>\($0.1)</em>" }
        s = s.replacing(#/(^|[^\w])_([^_]+)_(?![\w])/#) { "\($0.1)<em>\($0.2)</em>" }
        s = s.replacing(#/~~([^~]+)~~/#) { "<del>\($0.1)</del>" }
        return s
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
