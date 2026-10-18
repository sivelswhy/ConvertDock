import AVFoundation
import UniformTypeIdentifiers

/// Découpe audio / vidéo : un éditeur de trim natif s'ouvre, puis seule la plage choisie est exportée.
enum TrimTools {
    static var all: [Tool] {
        [
            Tool(id: "video.trim", title: "Couper la vidéo (trim)", subtitle: "Choisir le début et la fin",
                 symbol: "timeline.selection", category: .video, inputs: [.movie],
                 keywords: ["trim", "couper", "découper", "rogner", "raccourcir", "extrait", "cut"],
                 configure: { url in await TrimEditor.present(url) }) { inputs, ctx in
                try await inputs.asyncMap { url in try await trimVideo(url, ctx: ctx) }
            },
            Tool(id: "audio.trim", title: "Couper l'audio (trim)", subtitle: "Choisir le début et la fin",
                 symbol: "waveform.badge.minus", category: .audio, inputs: [.audio],
                 keywords: ["trim", "couper", "découper", "rogner", "raccourcir", "extrait", "sonnerie", "cut"],
                 configure: { url in await TrimEditor.present(url) }) { inputs, ctx in
                try await inputs.asyncMap { url in try await trimAudio(url, ctx: ctx) }
            },
        ]
    }

    private static func timeRange(_ p: ToolParameters) -> CMTimeRange? {
        guard let start = p.trimStart, let end = p.trimEnd, end > start else { return nil }
        return CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                           end: CMTime(seconds: end, preferredTimescale: 600))
    }

    static func trimVideo(_ url: URL, ctx: JobContext) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let ext = url.pathExtension.lowercased()
        // Sans réencodage quand le conteneur le permet : rapide et sans perte.
        let (preset, type, outExt): (String, AVFileType, String) = switch ext {
        case "mov": (AVAssetExportPresetPassthrough, .mov, "mov")
        case "mp4": (AVAssetExportPresetPassthrough, .mp4, "mp4")
        case "m4v": (AVAssetExportPresetPassthrough, .m4v, "m4v")
        default: (AVAssetExportPresetHighestQuality, .mp4, "mp4")
        }
        let out = ctx.output(for: url, ext: outExt, suffix: "extrait")
        try await VideoTools.exportAsset(asset, preset: preset, to: out, type: type,
                                         timeRange: timeRange(ctx.parameters), progress: ctx.progress)
        return out
    }

    static func trimAudio(_ url: URL, ctx: JobContext) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        let p = ctx.parameters
        // Formats lisibles en PCM : découpe à l'échantillon près dans le même format.
        if ["wav", "aif", "aiff", "caf", "flac"].contains(ext) {
            let out = ctx.output(for: url, ext: ext, suffix: "extrait")
            let source = try AVAudioFile(forReading: url)
            var settings = source.fileFormat.settings
            settings.removeValue(forKey: AVSampleRateKey)
            settings.removeValue(forKey: AVNumberOfChannelsKey)
            let range = (p.trimStart ?? 0)...(p.trimEnd ?? Double(source.length) / source.processingFormat.sampleRate)
            try AudioTools.transcode(url, to: out, settings: settings, range: range, progress: ctx.progress)
            return out
        }
        let out = ctx.output(for: url, ext: "m4a", suffix: "extrait")
        try await VideoTools.exportAsset(AVURLAsset(url: url), preset: AVAssetExportPresetAppleM4A, to: out, type: .m4a,
                                         timeRange: timeRange(p), progress: ctx.progress)
        return out
    }
}

extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self { results.append(try await transform(element)) }
        return results
    }
}
