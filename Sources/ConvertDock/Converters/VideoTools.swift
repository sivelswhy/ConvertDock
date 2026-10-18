import AVFoundation
import UniformTypeIdentifiers

enum VideoTools {
    static var all: [Tool] {
        [
            export(id: "video.to.mp4", title: "Convert to MP4 (H.264)", subtitle: "Plays everywhere",
                   preset: AVAssetExportPresetHighestQuality, type: .mp4, ext: "mp4", excludes: [.mpeg4Movie],
                   keywords: ["mp4", "h264", "convertir", "compatible"]),
            export(id: "video.to.mov", title: "Convert to MOV", subtitle: "QuickTime",
                   preset: AVAssetExportPresetPassthrough, type: .mov, ext: "mov", excludes: [.quickTimeMovie],
                   keywords: ["mov", "quicktime", "convertir"]),
            export(id: "video.to.hevc", title: "Convert to HEVC (H.265)", subtitle: "Same quality, smaller file",
                   preset: AVAssetExportPresetHEVCHighestQuality, type: .mp4, ext: "mp4", suffix: "HEVC",
                   keywords: ["hevc", "h265", "x265", "compresser"]),
            export(id: "video.to.m4v", title: "Convert to M4V", subtitle: "Apple TV / iTunes format",
                   preset: AVAssetExportPresetHighestQuality, type: .m4v, ext: "m4v", excludes: [UTType("com.apple.m4v-video")].compactMap { $0 },
                   keywords: ["m4v", "itunes", "apple tv"]),
            export(id: "video.1080", title: "Resize to 1080p", subtitle: "1920 × 1080",
                   preset: AVAssetExportPreset1920x1080, type: .mp4, ext: "mp4", suffix: "1080p",
                   keywords: ["1080p", "full hd", "redimensionner", "resize"]),
            export(id: "video.720", title: "Compress to 720p", subtitle: "Great for sharing",
                   preset: AVAssetExportPreset1280x720, type: .mp4, ext: "mp4", suffix: "720p",
                   keywords: ["720p", "compresser", "compress", "léger", "partager"]),
            export(id: "video.480", title: "Compress heavily (480p)", subtitle: "Smallest file",
                   preset: AVAssetExportPreset640x480, type: .mp4, ext: "mp4", suffix: "480p",
                   keywords: ["480p", "compresser", "mail", "léger"]),
            export(id: "video.audio", title: "Extract audio (M4A)", subtitle: "Soundtrack only",
                   preset: AVAssetExportPresetAppleM4A, type: .m4a, ext: "m4a", excludes: [],
                   keywords: ["audio", "son", "extraire", "musique", "m4a", "aac"]),
            Tool(id: "video.to.mp3", title: "Extract audio (MP3)", subtitle: "Soundtrack as MP3",
                 symbol: "music.note", category: .video, inputs: [.movie],
                 keywords: ["audio", "son", "extraire", "musique", "mp3"]) { inputs, ctx in
                try await inputs.asyncMap { url in
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
                    defer { try? FileManager.default.removeItem(at: tmp) }
                    try await exportAsset(AVURLAsset(url: url), preset: AVAssetExportPresetAppleM4A, to: tmp, type: .m4a) { ctx.progress($0 * 0.5) }
                    let out = ctx.output(for: url, ext: "mp3")
                    try MP3Encoder.encode(tmp, to: out, mode: .vbr(quality: 2)) { ctx.progress(0.5 + $0 * 0.5) }
                    return out
                }
            },
            Tool(id: "video.to.gif", title: "Convert to animated GIF", subtitle: "10 fps, 480 px, 20 s max",
                 symbol: "play.square.stack", category: .video, inputs: [.movie],
                 keywords: ["gif", "animation", "animé", "meme"]) { inputs, ctx in
                var outputs: [URL] = []
                for url in inputs {
                    let out = ctx.output(for: url, ext: "gif")
                    try await makeGIF(url, to: out, progress: ctx.progress)
                    outputs.append(out)
                }
                return outputs
            },
            Tool(id: "video.poster", title: "Capture a frame", subtitle: "Middle frame of the video → PNG",
                 symbol: "camera.viewfinder", category: .video, inputs: [.movie],
                 keywords: ["capture", "screenshot", "miniature", "poster", "frame", "image"]) { inputs, ctx in
                var outputs: [URL] = []
                for url in inputs {
                    let asset = AVURLAsset(url: url)
                    let duration = try await asset.load(.duration)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.requestedTimeToleranceBefore = .zero
                    generator.requestedTimeToleranceAfter = .zero
                    let (image, _) = try await generator.image(at: CMTimeMultiplyByFloat64(duration, multiplier: 0.5))
                    let out = ctx.output(for: url, ext: "png", suffix: "capture")
                    try ImageIOHelpers.write(image, to: out, type: .png)
                    outputs.append(out)
                }
                return outputs
            },
        ]
    }

    private static func export(
        id: String, title: String, subtitle: String, preset: String, type: AVFileType, ext: String,
        suffix: String? = nil, excludes: [UTType] = [], keywords: [String]
    ) -> Tool {
        let isAudioOnly = type == .m4a
        return Tool(id: id, title: title, subtitle: subtitle,
                    symbol: isAudioOnly ? "waveform.badge.plus" : "film.stack",
                    category: .video, inputs: [.movie], excludes: excludes, keywords: keywords) { inputs, ctx in
            var outputs: [URL] = []
            for (index, url) in inputs.enumerated() {
                let out = ctx.output(for: url, ext: ext, suffix: suffix)
                try await exportAsset(AVURLAsset(url: url), preset: preset, to: out, type: type) { p in
                    ctx.progress((Double(index) + p) / Double(inputs.count))
                }
                outputs.append(out)
            }
            return outputs
        }
    }

    static func exportAsset(_ asset: AVAsset, preset: String, to out: URL, type: AVFileType, timeRange: CMTimeRange? = nil,
                            progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ToolError.unsupported(L("This export preset is not available for this file."))
        }
        session.shouldOptimizeForNetworkUse = true
        if let timeRange { session.timeRange = timeRange }
        if type == .m4a, (try? await asset.loadTracks(withMediaType: .audio).isEmpty) != false {
            throw ToolError.unsupported(L("This file has no audio track."))
        }
        let monitor = Task {
            for await state in session.states(updateInterval: 0.2) {
                if case .exporting(let p) = state { progress(p.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        do {
            try await session.export(to: out, as: type)
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }

    static func makeGIF(_ url: URL, to out: URL, progress: @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        let duration = min(try await asset.load(.duration).seconds, 20)
        guard duration > 0 else { throw ToolError.failed(L("Empty video.")) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let tolerance = CMTime(value: 1, timescale: 20)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let fps = 10.0
        let total = max(1, Int(duration * fps))
        var frames: [CGImage] = []
        for i in 0..<total {
            let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            if let (image, _) = try? await generator.image(at: time) { frames.append(image) }
            progress(Double(i + 1) / Double(total))
        }
        guard !frames.isEmpty else { throw ToolError.failed(L("Could not read the video frames.")) }
        try ImageIOHelpers.writeMulti(frames, to: out, type: .gif, frameDelay: 1 / fps)
    }
}
