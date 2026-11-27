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
            Tool(id: "video.compress.25mb", title: "Compress for email (≤ 25 MB)", subtitle: "Best quality that fits, for mail and Discord",
                 symbol: "envelope.badge", category: .video, inputs: [.movie],
                 keywords: ["compresser", "email", "mail", "discord", "whatsapp", "envoyer", "25 mo", "taille", "léger"]) { inputs, ctx in
                try await inputs.asyncMap { url in
                    let asset = AVURLAsset(url: url)
                    let limit: Int64 = 25_000_000
                    // shortcut: on prend le meilleur préréglage dont l'estimation tient sous 25 Mo ; l'estimation peut
                    // dépasser de quelques pour cent. Passer à AVAssetWriter avec un débit calculé si la limite doit être stricte.
                    let presets = [AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720, AVAssetExportPreset960x540,
                                   AVAssetExportPreset640x480, AVAssetExportPresetMediumQuality, AVAssetExportPresetLowQuality]
                    var chosen = AVAssetExportPresetLowQuality
                    for preset in presets {
                        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
                        session.outputFileType = .mp4
                        if let size = try? await session.estimatedOutputFileLengthInBytes, size > 0, size <= limit {
                            chosen = preset
                            break
                        }
                    }
                    let out = ctx.output(for: url, ext: "mp4", suffix: L("compressed"))
                    try await VideoTools.exportAsset(asset, preset: chosen, to: out, type: .mp4, progress: ctx.progress)
                    return out
                }
            },
            Tool(id: "video.merge", title: "Join videos", subtitle: "One after the other, in order → MP4",
                 symbol: "film.stack", category: .video, inputs: [.movie],
                 keywords: ["fusionner", "joindre", "assembler", "concaténer", "merge", "join", "montage", "combiner"],
                 combinesInputs: true, minimumInputs: 2) { inputs, ctx in
                // shortcut: l'orientation et la taille du premier clip s'appliquent à tous ; les clips de formats différents
                // seront déformés. Passer par une AVVideoComposition avec une instruction par clip si besoin.
                let composition = AVMutableComposition()
                let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                for (index, url) in inputs.enumerated() {
                    let asset = AVURLAsset(url: url)
                    let range = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
                    let at = composition.duration
                    if let track = try await asset.loadTracks(withMediaType: .video).first {
                        try video?.insertTimeRange(range, of: track, at: at)
                        if index == 0 { video?.preferredTransform = try await track.load(.preferredTransform) }
                    }
                    if let track = try await asset.loadTracks(withMediaType: .audio).first {
                        try audio?.insertTimeRange(range, of: track, at: at)
                    }
                }
                if let audio, audio.segments.isEmpty { composition.removeTrack(audio) }
                let out = ctx.output(for: inputs[0], ext: "mp4", suffix: L("and %d more", inputs.count - 1))
                try await VideoTools.exportAsset(composition, preset: AVAssetExportPresetHighestQuality, to: out, type: .mp4, progress: ctx.progress)
                return [out]
            },
            Tool(id: "video.replace.audio", title: "Replace the soundtrack", subtitle: "Select a video and an audio file",
                 symbol: "music.note.tv", category: .video, inputs: [.movie, .audio],
                 keywords: ["musique", "bande son", "audio", "remplacer", "doubler", "soundtrack", "voix off"],
                 combinesInputs: true, minimumInputs: 2) { inputs, ctx in
                var videoURL: URL?, audioURL: URL?
                for url in inputs {
                    let hasVideo = try await !AVURLAsset(url: url).loadTracks(withMediaType: .video).isEmpty
                    if hasVideo, videoURL == nil { videoURL = url } else if !hasVideo, audioURL == nil { audioURL = url }
                }
                guard let videoURL, let audioURL else { throw ToolError.unsupported(L("Select one video and one audio file.")) }
                let videoAsset = AVURLAsset(url: videoURL), audioAsset = AVURLAsset(url: audioURL)
                let duration = try await videoAsset.load(.duration)
                let composition = AVMutableComposition()
                for track in try await videoAsset.loadTracks(withMediaType: .video) {
                    let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                    try copy?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
                    copy?.preferredTransform = try await track.load(.preferredTransform)
                }
                if let track = try await audioAsset.loadTracks(withMediaType: .audio).first {
                    let audioDuration = try await audioAsset.load(.duration)
                    let copy = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    try copy?.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: track, at: .zero)
                }
                let out = ctx.output(for: videoURL, ext: "mp4", suffix: L("new sound"))
                try await VideoTools.exportAsset(composition, preset: AVAssetExportPresetHighestQuality, to: out, type: .mp4, progress: ctx.progress)
                return [out]
            },
            Tool(id: "video.contact.sheet", title: "Contact sheet", subtitle: "16 thumbnails on one image → JPEG",
                 symbol: "square.grid.4x3.fill", category: .video, inputs: [.movie],
                 keywords: ["planche contact", "contact sheet", "miniatures", "aperçu", "grille", "storyboard"]) { inputs, ctx in
                try await inputs.asyncMap { url in
                    let asset = AVURLAsset(url: url)
                    let duration = try await asset.load(.duration).seconds
                    guard duration > 0 else { throw ToolError.failed(L("Empty video.")) }
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 480, height: 480)
                    var frames: [CGImage] = []
                    for i in 0..<16 {
                        let time = CMTime(seconds: duration * (Double(i) + 0.5) / 16, preferredTimescale: 600)
                        if let (image, _) = try? await generator.image(at: time) { frames.append(image) }
                        ctx.progress(Double(i + 1) / 16)
                    }
                    guard let first = frames.first else { throw ToolError.failed(L("Could not read the video frames.")) }
                    let gap = 8, cw = first.width, ch = first.height
                    let width = 4 * cw + 5 * gap, height = 4 * ch + 5 * gap
                    guard let sheet = ImageIOHelpers.context(width: width, height: height) else { throw ToolError.failed(L("Failed to render the image.")) }
                    sheet.setFillColor(.black)
                    sheet.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    for (i, frame) in frames.enumerated() {
                        let x = gap + (i % 4) * (cw + gap), y = height - (i / 4 + 1) * (ch + gap)
                        sheet.draw(frame, in: CGRect(x: x, y: y, width: cw, height: ch))
                    }
                    guard let image = sheet.makeImage() else { throw ToolError.failed(L("Failed to render the image.")) }
                    let out = ctx.output(for: url, ext: "jpg", suffix: L("contact sheet"))
                    try ImageIOHelpers.write(image, to: out, type: .jpeg, quality: 0.88)
                    return out
                }
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
