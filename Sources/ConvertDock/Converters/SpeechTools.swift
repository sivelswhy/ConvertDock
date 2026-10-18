import AVFoundation
import NaturalLanguage
import Speech
import UniformTypeIdentifiers

/// Parole ⇄ texte : transcription (texte, sous-titres) et lecture à voix haute, sur l'appareil.
enum SpeechTools {
    static var all: [Tool] {
        [
            Tool(id: "ai.transcribe", title: "Transcribe to text", subtitle: "Speech recognition → .txt",
                 symbol: "waveform.and.mic", category: .intelligence, inputs: [.audio, .movie],
                 keywords: ["transcrire", "transcription", "dictée", "parole", "speech", "texte", "réunion", "podcast"]) { inputs, ctx in
                try await inputs.asyncMap { url in
                    let segments = try await transcribe(url, progress: ctx.progress)
                    let text = segments.map(\.text).joined(separator: " ")
                    let out = ctx.output(for: url, ext: "txt", suffix: L("transcript"))
                    try text.write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "ai.subtitles", title: "Generate subtitles (.srt)", subtitle: "Timed captions from speech",
                 symbol: "captions.bubble", category: .intelligence, inputs: [.audio, .movie],
                 keywords: ["sous-titres", "subtitles", "srt", "captions", "transcrire", "vidéo"]) { inputs, ctx in
                try await inputs.asyncMap { url in
                    let segments = try await transcribe(url, progress: ctx.progress)
                    let out = ctx.output(for: url, ext: "srt")
                    try Subtitles.srt(from: captions(from: segments)).write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            },
            Tool(id: "ai.speak", title: "Read aloud to audio", subtitle: "Text → spoken M4A",
                 symbol: "speaker.wave.3", category: .intelligence,
                 inputs: [.plainText, .rtf, .docx, .doc, .odt, .html, .markdown, .pdf],
                 keywords: ["lire", "voix", "synthèse vocale", "text to speech", "tts", "audio", "livre audio", "parler"]) { inputs, ctx in
                try await inputs.asyncMap { url in
                    let text: String
                    if url.contentType?.conforms(to: .pdf) == true {
                        text = try PDFTools.open(url).string ?? ""
                    } else {
                        text = try await DocumentTools.load(url).string
                    }
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError.failed(L("No text detected.")) }
                    let out = ctx.output(for: url, ext: "m4a")
                    try await speak(text, to: out)
                    return out
                }
            },
        ]
    }

    struct Segment {
        let text: String
        let start: Double
        let end: Double
    }

    // MARK: Transcription

    static func transcribe(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [Segment] {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else {
            throw ToolError.failed(L("Speech recognition is not allowed. Enable it in System Settings › Privacy & Security › Speech Recognition."))
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw ToolError.failed(L("Speech recognition is unavailable for this language."))
        }

        // La reconnaissance attend un fichier audio : on extrait la piste des vidéos.
        var audioURL = url
        var temporary: URL?
        if url.contentType?.conforms(to: .movie) == true {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            try await VideoTools.exportAsset(AVURLAsset(url: url), preset: AVAssetExportPresetAppleM4A, to: tmp, type: .m4a) { p in progress(p * 0.2) }
            audioURL = tmp
            temporary = tmp
        }
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }

        let duration = (try? await AVURLAsset(url: audioURL).load(.duration).seconds) ?? 0
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result {
                    if let last = result.bestTranscription.segments.last, duration > 0 {
                        progress(0.2 + 0.8 * min(1, (last.timestamp + last.duration) / duration))
                    }
                    if result.isFinal {
                        finished = true
                        continuation.resume(returning: result)
                    }
                } else if let error {
                    finished = true
                    continuation.resume(throwing: error)
                }
            }
        }
        let segments = result.bestTranscription.segments.map {
            Segment(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
        }
        guard !segments.isEmpty else { throw ToolError.failed(L("No speech detected.")) }
        return segments
    }

    /// Regroupe les mots en sous-titres lisibles : 42 caractères ou 4 s maximum, coupure sur la ponctuation.
    static func captions(from words: [Segment]) -> [Segment] {
        var captions: [Segment] = []
        var current: [Segment] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            captions.append(Segment(text: current.map(\.text).joined(separator: " "), start: first.start, end: last.end))
            current.removeAll()
        }
        for word in words {
            if let first = current.first {
                let length = current.map(\.text.count).reduce(0, +) + current.count + word.text.count
                let pause = word.start - (current.last?.end ?? word.start)
                if length > 42 || word.end - first.start > 4 || pause > 0.8 { flush() }
            }
            current.append(word)
            if let char = word.text.last, ".!?".contains(char) { flush() }
        }
        flush()
        return captions
    }

    // MARK: Synthèse vocale

    static func speak(_ text: String, to out: URL) async throws {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        let language = recognizer.dominantLanguage?.rawValue ?? Locale.current.language.languageCode?.identifier ?? "en"
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language)

        let synthesizer = AVSpeechSynthesizer()
        var file: AVAudioFile?
        var failure: Error?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var done = false
            synthesizer.write(utterance) { buffer in
                guard !done else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    done = true
                    continuation.resume()
                    return
                }
                do {
                    if file == nil {
                        file = try AVAudioFile(forWriting: out, settings: [
                            AVFormatIDKey: kAudioFormatMPEG4AAC,
                            AVSampleRateKey: pcm.format.sampleRate,
                            AVNumberOfChannelsKey: pcm.format.channelCount,
                        ], commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
                    }
                    try file?.write(from: pcm)
                } catch {
                    failure = error
                    done = true
                    continuation.resume()
                }
            }
        }
        _ = synthesizer
        file = nil
        if let failure { throw failure }
        guard FileManager.default.fileExists(atPath: out.path) else { throw ToolError.failed(L("Speech synthesis failed.")) }
    }
}
