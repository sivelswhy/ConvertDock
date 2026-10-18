import AVFoundation
import UniformTypeIdentifiers

enum AudioTools {
    static var all: [Tool] {
        [
            Tool(id: "audio.to.m4a", title: "Convert to M4A (AAC)", subtitle: "Compressed, high quality",
                 symbol: "waveform", category: .audio, inputs: [.audio], excludes: [.mpeg4Audio],
                 keywords: ["m4a", "aac", "convertir", "compresser"]) { inputs, ctx in
                var outputs: [URL] = []
                for url in inputs {
                    let out = ctx.output(for: url, ext: "m4a")
                    try await VideoTools.exportAsset(AVURLAsset(url: url), preset: AVAssetExportPresetAppleM4A, to: out, type: .m4a, progress: ctx.progress)
                    outputs.append(out)
                }
                return outputs
            },
            mp3(id: "audio.to.mp3", title: "Convert to MP3", subtitle: "Plays everywhere, high-quality VBR",
                mode: .vbr(quality: 2), suffix: nil, excludes: [.mp3], keywords: ["mp3", "lame", "compatible", "musique"]),
            mp3(id: "audio.to.mp3.320", title: "Convert to MP3 320 kbps", subtitle: "Maximum MP3 quality",
                mode: .cbr(kbps: 320), suffix: "320k", excludes: [], keywords: ["mp3", "320", "haute qualité", "cbr"]),
            pcm(id: "audio.to.wav", name: "WAV", ext: "wav", type: .wav, bigEndian: false, keywords: ["wav", "wave", "non compressé"]),
            pcm(id: "audio.to.aiff", name: "AIFF", ext: "aiff", type: .aiff, bigEndian: true, keywords: ["aiff", "aif", "non compressé"]),
            pcm(id: "audio.to.caf", name: "CAF", ext: "caf", type: UTType("com.apple.coreaudio-format") ?? .audio, bigEndian: false, keywords: ["caf", "core audio"]),
            encoded(id: "audio.to.flac", title: "Convert to FLAC", subtitle: "Lossless, compressed",
                    ext: "flac", type: .flac, format: kAudioFormatFLAC, keywords: ["flac", "lossless", "sans perte"]),
            encoded(id: "audio.to.alac", title: "Convert to Apple Lossless", subtitle: "ALAC .m4a, lossless",
                    ext: "m4a", suffix: "ALAC", type: nil, format: kAudioFormatAppleLossless, keywords: ["alac", "lossless", "sans perte", "apple"]),
            encoded(id: "audio.to.opus", title: "Convert to Opus", subtitle: "Very efficient codec, .caf container",
                    ext: "caf", suffix: "Opus", type: nil, format: kAudioFormatOpus, sampleRate: 48_000,
                    keywords: ["opus", "voix", "podcast", "léger", "efficace"]),
            encoded(id: "audio.to.aac256", title: "Convert to M4A 256 kbps", subtitle: "High-quality AAC",
                    ext: "m4a", suffix: "256k", type: nil, format: kAudioFormatMPEG4AAC, bitRate: 256_000,
                    keywords: ["aac", "m4a", "256", "haute qualité", "itunes", "débit", "bitrate"]),
            encoded(id: "audio.to.aac96", title: "Convert to M4A 96 kbps", subtitle: "Light AAC, for voice and sharing",
                    ext: "m4a", suffix: "96k", type: nil, format: kAudioFormatMPEG4AAC, bitRate: 96_000,
                    keywords: ["aac", "m4a", "96", "léger", "compresser", "débit", "bitrate"]),
        ]
    }

    private static func mp3(id: String, title: String, subtitle: String, mode: MP3Encoder.Mode, suffix: String?,
                            excludes: [UTType], keywords: [String]) -> Tool {
        Tool(id: id, title: title, subtitle: subtitle, symbol: "music.note", category: .audio, inputs: [.audio],
             excludes: excludes, keywords: ["convertir"] + keywords) { inputs, ctx in
            try inputs.map { url in
                let out = ctx.output(for: url, ext: "mp3", suffix: suffix)
                try MP3Encoder.encode(url, to: out, mode: mode, progress: ctx.progress)
                return out
            }
        }
    }

    private static func pcm(id: String, name: String, ext: String, type: UTType, bigEndian: Bool, keywords: [String]) -> Tool {
        Tool(id: id, title: "Convert to \(name)", subtitle: "16-bit PCM, studio quality",
             symbol: "waveform.path", category: .audio, inputs: [.audio], excludes: [type],
             keywords: ["convertir"] + keywords) { inputs, ctx in
            try inputs.map { url in
                let out = ctx.output(for: url, ext: ext)
                try transcode(url, to: out, settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: bigEndian,
                    AVLinearPCMIsNonInterleaved: false,
                ], progress: ctx.progress)
                return out
            }
        }
    }

    private static func encoded(id: String, title: String, subtitle: String, ext: String, suffix: String? = nil,
                                type: UTType?, format: AudioFormatID, sampleRate: Double? = nil, bitRate: Int? = nil,
                                keywords: [String]) -> Tool {
        Tool(id: id, title: title, subtitle: subtitle, symbol: "waveform.badge.magnifyingglass", category: .audio,
             inputs: [.audio], excludes: type.map { [$0] } ?? [], keywords: ["convertir"] + keywords) { inputs, ctx in
            try inputs.map { url in
                let out = ctx.output(for: url, ext: ext, suffix: suffix)
                var settings: [String: Any] = [AVFormatIDKey: format]
                if let sampleRate { settings[AVSampleRateKey] = sampleRate }
                if let bitRate { settings[AVEncoderBitRateKey] = bitRate }
                try transcode(url, to: out, settings: settings, progress: ctx.progress)
                return out
            }
        }
    }

    /// Transcodage par blocs via AVAudioFile (le format est déduit de l'extension de sortie).
    static func transcode(_ url: URL, to out: URL, settings extra: [String: Any], range: ClosedRange<Double>? = nil,
                          progress: @Sendable (Double) -> Void) throws {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        var endFrame = input.length
        if let range {
            input.framePosition = AVAudioFramePosition(range.lowerBound * format.sampleRate)
            endFrame = min(input.length, AVAudioFramePosition(range.upperBound * format.sampleRate))
        }
        let startFrame = input.framePosition
        var settings = extra
        if settings[AVSampleRateKey] == nil { settings[AVSampleRateKey] = format.sampleRate }
        settings[AVNumberOfChannelsKey] = format.channelCount
        // L'AAC exige 44,1/48 kHz pour les débits élevés ; en mono, le débit cible est réparti sur un seul canal.
        if (settings[AVFormatIDKey] as? AudioFormatID) == kAudioFormatMPEG4AAC {
            settings[AVSampleRateKey] = max(44_100, format.sampleRate)
            if let bitRate = settings[AVEncoderBitRateKey] as? Int, format.channelCount == 1 {
                settings[AVEncoderBitRateKey] = bitRate / 2
            }
        }
        do {
            let output = try AVAudioFile(forWriting: out, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let capacity: AVAudioFrameCount = 32_768
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw ToolError.failed(L("Not enough memory."))
            }
            let total = max(1, Double(endFrame - startFrame))
            // Rééchantillonnage si le format de sortie l'impose (ex. Opus à 48 kHz).
            let outFormat = output.processingFormat
            let converter = outFormat.sampleRate == format.sampleRate ? nil : AVAudioConverter(from: format, to: outFormat)
            let ratio = outFormat.sampleRate / format.sampleRate
            let converted = converter.flatMap { _ in AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(Double(capacity) * ratio) + 1024) }
            while input.framePosition < endFrame {
                let remaining = AVAudioFrameCount(endFrame - input.framePosition)
                try input.read(into: buffer, frameCount: min(capacity, remaining))
                if buffer.frameLength == 0 { break }
                if let converter, let converted {
                    var supplied = false
                    var conversionError: NSError?
                    converter.convert(to: converted, error: &conversionError) { _, status in
                        if supplied { status.pointee = .noDataNow; return nil }
                        supplied = true
                        status.pointee = .haveData
                        return buffer
                    }
                    if let conversionError { throw conversionError }
                    if converted.frameLength > 0 { try output.write(from: converted) }
                } else {
                    try output.write(from: buffer)
                }
                progress(Double(input.framePosition - startFrame) / total)
            }
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }
}
