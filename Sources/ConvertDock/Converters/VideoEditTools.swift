import AVFoundation
import CoreImage
import UniformTypeIdentifiers

/// Montage léger : ProRes, son, vitesse, rotation, extraction des images.
enum VideoEditTools {
    static var all: [Tool] {
        [
            proRes(id: "video.to.prores422", title: "Convert to ProRes 422", subtitle: "Editing quality, large file",
                   preset: AVAssetExportPresetAppleProRes422LPCM, suffix: "ProRes 422"),
            proRes(id: "video.to.prores4444", title: "Convert to ProRes 4444", subtitle: "Mastering quality, keeps transparency",
                   preset: AVAssetExportPresetAppleProRes4444LPCM, suffix: "ProRes 4444"),
            Tool(id: "video.mute", title: "Remove sound", subtitle: "Same video, no audio track",
                 symbol: "speaker.slash", category: .video, inputs: [.movie],
                 keywords: ["muet", "mute", "son", "audio", "supprimer", "silence", "retirer"]) { inputs, ctx in
                try await inputs.asyncMap { url in
                    let asset = AVURLAsset(url: url)
                    let composition = AVMutableComposition()
                    let duration = try await asset.load(.duration)
                    for track in try await asset.loadTracks(withMediaType: .video) {
                        let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                        try copy?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
                        copy?.preferredTransform = try await track.load(.preferredTransform)
                    }
                    let out = ctx.output(for: url, ext: "mov", suffix: L("muted"))
                    try await VideoTools.exportAsset(composition, preset: AVAssetExportPresetPassthrough, to: out, type: .mov, progress: ctx.progress)
                    return out
                }
            },
            speed(id: "video.speed.2x", title: "Speed up ×2", subtitle: "Twice as fast", factor: 2, suffix: "x2"),
            speed(id: "video.speed.half", title: "Slow down ×0.5", subtitle: "Slow motion", factor: 0.5, suffix: "x0.5"),
            Tool(id: "video.rotate", title: "Rotate video 90°", subtitle: "Clockwise, without re-encoding",
                 symbol: "rotate.right", category: .video, inputs: [.movie],
                 keywords: ["pivoter", "rotation", "tourner", "rotate", "portrait", "paysage"]) { inputs, ctx in
                try await inputs.asyncMap { url in
                    let asset = AVURLAsset(url: url)
                    let composition = AVMutableComposition()
                    let duration = try await asset.load(.duration)
                    let range = CMTimeRange(start: .zero, duration: duration)
                    for track in try await asset.loadTracks(withMediaType: .video) {
                        let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                        try copy?.insertTimeRange(range, of: track, at: .zero)
                        let size = try await track.load(.naturalSize).applying(try await track.load(.preferredTransform))
                        let rotation = CGAffineTransform(rotationAngle: .pi / 2).translatedBy(x: 0, y: -abs(size.height))
                        copy?.preferredTransform = try await track.load(.preferredTransform).concatenating(rotation)
                    }
                    for track in try await asset.loadTracks(withMediaType: .audio) {
                        let copy = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                        try copy?.insertTimeRange(range, of: track, at: .zero)
                    }
                    let out = ctx.output(for: url, ext: "mov", suffix: L("rotated"))
                    try await VideoTools.exportAsset(composition, preset: AVAssetExportPresetPassthrough, to: out, type: .mov, progress: ctx.progress)
                    return out
                }
            },
            Tool(id: "video.frames", title: "Extract all frames", subtitle: "Every frame as JPEG, in a folder",
                 symbol: "square.stack.3d.down.right", category: .video, inputs: [.movie],
                 keywords: ["images", "frames", "extraire", "séquence", "photogrammes", "jpg", "png"]) { inputs, ctx in
                try await inputs.asyncMap { url in try await extractFrames(url, progress: ctx.progress) }
            },
        ]
    }

    private static func proRes(id: String, title: String, subtitle: String, preset: String, suffix: String) -> Tool {
        Tool(id: id, title: title, subtitle: subtitle, symbol: "film.stack", category: .video, inputs: [.movie],
             keywords: ["prores", "montage", "final cut", "premiere", "davinci", "mov", "pro"]) { inputs, ctx in
            try await inputs.asyncMap { url in
                let out = ctx.output(for: url, ext: "mov", suffix: suffix)
                try await VideoTools.exportAsset(AVURLAsset(url: url), preset: preset, to: out, type: .mov, progress: ctx.progress)
                return out
            }
        }
    }

    private static func speed(id: String, title: String, subtitle: String, factor: Double, suffix: String) -> Tool {
        Tool(id: id, title: title, subtitle: subtitle, symbol: factor > 1 ? "hare" : "tortoise", category: .video, inputs: [.movie],
             keywords: ["vitesse", "speed", "accélérer", "ralenti", "slow motion", "timelapse", factor > 1 ? "rapide" : "lent"]) { inputs, ctx in
            try await inputs.asyncMap { url in
                let asset = AVURLAsset(url: url)
                let composition = AVMutableComposition()
                let duration = try await asset.load(.duration)
                let range = CMTimeRange(start: .zero, duration: duration)
                for mediaType in [AVMediaType.video, .audio] {
                    for track in try await asset.loadTracks(withMediaType: mediaType) {
                        let copy = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)
                        try copy?.insertTimeRange(range, of: track, at: .zero)
                        if mediaType == .video { copy?.preferredTransform = try await track.load(.preferredTransform) }
                    }
                }
                composition.scaleTimeRange(range, toDuration: CMTimeMultiplyByFloat64(duration, multiplier: 1 / factor))
                let out = ctx.output(for: url, ext: "mp4", suffix: suffix)
                try await VideoTools.exportAsset(composition, preset: AVAssetExportPresetHighestQuality, to: out, type: .mp4, progress: ctx.progress)
                return out
            }
        }
    }

    /// Décode toutes les images avec AVAssetReader et les enregistre en JPEG.
    static func extractFrames(_ url: URL, progress: @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ToolError.failed(L("This file has no video track."))
        }
        let duration = try await asset.load(.duration).seconds
        let transform = try await track.load(.preferredTransform)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ToolError.unreadable(url) }

        let folder = try PDFTools.makeFolder(for: url, name: L("frames"))
        let context = ImageIOHelpers.ciContext
        var index = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let image = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
            let shifted = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            if let cg = context.createCGImage(shifted, from: shifted.extent) {
                index += 1
                try ImageIOHelpers.write(cg, to: folder.appendingPathComponent(String(format: "frame-%05d.jpg", index)), type: .jpeg, quality: 0.9)
            }
            if duration > 0 { progress(min(1, CMSampleBufferGetPresentationTimeStamp(sample).seconds / duration)) }
        }
        if reader.status == .failed { throw reader.error ?? ToolError.unreadable(url) }
        return folder
    }
}
