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
            pcm(id: "audio.to.wav", name: "WAV", ext: "wav", type: .wav, bigEndian: false, keywords: ["wav", "wave", "non compressé"]),
            pcm(id: "audio.to.aiff", name: "AIFF", ext: "aiff", type: .aiff, bigEndian: true, keywords: ["aiff", "aif", "non compressé"]),
            pcm(id: "audio.to.caf", name: "CAF", ext: "caf", type: UTType("com.apple.coreaudio-format") ?? .audio, bigEndian: false, keywords: ["caf", "core audio"]),
            encoded(id: "audio.to.flac", title: "Convert to FLAC", subtitle: "Lossless, compressed",
                    ext: "flac", type: .flac, format: kAudioFormatFLAC, keywords: ["flac", "lossless", "sans perte"]),
            encoded(id: "audio.to.alac", title: "Convert to Apple Lossless", subtitle: "ALAC .m4a, lossless",
                    ext: "m4a", suffix: "ALAC", type: nil, format: kAudioFormatAppleLossless, keywords: ["alac", "lossless", "sans perte", "apple"]),
        ]
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
                                type: UTType?, format: AudioFormatID, keywords: [String]) -> Tool {
        Tool(id: id, title: title, subtitle: subtitle, symbol: "waveform.badge.magnifyingglass", category: .audio,
             inputs: [.audio], excludes: type.map { [$0] } ?? [], keywords: ["convertir"] + keywords) { inputs, ctx in
            try inputs.map { url in
                let out = ctx.output(for: url, ext: ext, suffix: suffix)
                try transcode(url, to: out, settings: [AVFormatIDKey: format], progress: ctx.progress)
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
        settings[AVSampleRateKey] = format.sampleRate
        settings[AVNumberOfChannelsKey] = format.channelCount
        do {
            let output = try AVAudioFile(forWriting: out, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let capacity: AVAudioFrameCount = 32_768
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw ToolError.failed(L("Not enough memory."))
            }
            let total = max(1, Double(endFrame - startFrame))
            while input.framePosition < endFrame {
                let remaining = AVAudioFrameCount(endFrame - input.framePosition)
                try input.read(into: buffer, frameCount: min(capacity, remaining))
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
                progress(Double(input.framePosition - startFrame) / total)
            }
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }
}
