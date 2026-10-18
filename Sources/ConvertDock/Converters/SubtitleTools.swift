import Foundation
import UniformTypeIdentifiers

/// Sous-titres SRT ⇄ WebVTT.
enum SubtitleTools {
    static var all: [Tool] {
        [
            Tool(id: "subs.srt.to.vtt", title: "SRT → WebVTT", subtitle: "Subtitles for the web",
                 symbol: "captions.bubble", category: .document, inputs: [], inputExtensions: ["srt"],
                 keywords: ["sous-titres", "subtitles", "srt", "vtt", "webvtt", "html5"]) { inputs, ctx in
                try inputs.map { url in
                    let cues = Subtitles.parse(try String(contentsOf: url, encoding: .utf8))
                    guard !cues.isEmpty else { throw ToolError.failed(L("No subtitles found.")) }
                    let out = ctx.output(for: url, ext: "vtt")
                    try Subtitles.vtt(from: cues).write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "subs.vtt.to.srt", title: "WebVTT → SRT", subtitle: "Subtitles for video players",
                 symbol: "captions.bubble", category: .document, inputs: [], inputExtensions: ["vtt"],
                 keywords: ["sous-titres", "subtitles", "srt", "vtt", "webvtt"]) { inputs, ctx in
                try inputs.map { url in
                    let cues = Subtitles.parse(try String(contentsOf: url, encoding: .utf8))
                    guard !cues.isEmpty else { throw ToolError.failed(L("No subtitles found.")) }
                    let out = ctx.output(for: url, ext: "srt")
                    try Subtitles.srt(from: cues).write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
        ]
    }
}

enum Subtitles {
    typealias Cue = SpeechTools.Segment

    /// Lit des blocs « 00:00:01,000 --> 00:00:03,500 » (SRT) ou « 00:01.000 --> 00:03.500 » (VTT).
    static func parse(_ text: String) -> [Cue] {
        var cues: [Cue] = []
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2, let start = seconds(parts[0]), let end = seconds(parts[1].split(separator: " ").first.map(String.init) ?? parts[1]) else { continue }
            let body = lines[(timingIndex + 1)...].joined(separator: "\n")
            cues.append(Cue(text: body, start: start, end: end))
        }
        return cues
    }

    static func srt(from cues: [Cue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start, separator: ",")) --> \(timestamp(cue.end, separator: ","))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    static func vtt(from cues: [Cue]) -> String {
        "WEBVTT\n\n" + cues.map { cue in
            "\(timestamp(cue.start, separator: ".")) --> \(timestamp(cue.end, separator: "."))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    private static func timestamp(_ t: Double, separator: String) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, separator, ms % 1000)
    }

    private static func seconds(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        let values = parts.compactMap { Double($0) }
        guard values.count == parts.count else { return nil }
        return values.reduce(0) { $0 * 60 + $1 }
    }
}
