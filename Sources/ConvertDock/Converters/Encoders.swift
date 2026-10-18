import AVFoundation
import CLame
import CoreGraphics
import libwebp

/// Encodeur MP3 basé sur LAME 3.100.
enum MP3Encoder {
    enum Mode {
        /// Débit variable, 0 = meilleure qualité … 9 = plus léger (V2 ≈ 190 kbit/s).
        case vbr(quality: Float)
        /// Débit constant en kbit/s.
        case cbr(kbps: Int32)
    }

    static func encode(_ url: URL, to out: URL, mode: Mode, range: ClosedRange<Double>? = nil,
                       progress: @Sendable (Double) -> Void) throws {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let channels = Int(format.channelCount)

        guard let lame = lame_init() else { throw ToolError.failed(L("Could not start the MP3 encoder.")) }
        defer { lame_close(lame) }
        lame_set_in_samplerate(lame, Int32(format.sampleRate))
        lame_set_num_channels(lame, Int32(min(channels, 2)))
        lame_set_mode(lame, channels == 1 ? MONO : JOINT_STEREO)
        lame_set_quality(lame, 2)
        lame_set_write_id3tag_automatic(lame, 0)
        switch mode {
        case .vbr(let quality):
            lame_set_VBR(lame, vbr_default)
            lame_set_VBR_quality(lame, quality)
        case .cbr(let kbps):
            lame_set_VBR(lame, vbr_off)
            lame_set_brate(lame, kbps)
            // Les débits élevés n'existent qu'en MPEG-1 (32–48 kHz) : on rééchantillonne si besoin.
            if kbps > 160 { lame_set_out_samplerate(lame, Int32(min(48_000, max(44_100, format.sampleRate)))) }
        }
        guard lame_init_params(lame) >= 0 else { throw ToolError.failed(L("Could not start the MP3 encoder.")) }

        var endFrame = input.length
        if let range {
            input.framePosition = AVAudioFramePosition(range.lowerBound * format.sampleRate)
            endFrame = min(input.length, AVAudioFramePosition(range.upperBound * format.sampleRate))
        }
        let startFrame = input.framePosition

        FileManager.default.createFile(atPath: out.path, contents: nil)
        let handle = try FileHandle(forWritingTo: out)
        defer { try? handle.close() }

        let capacity: AVAudioFrameCount = 8192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity),
              let channelData = buffer.floatChannelData else { throw ToolError.failed(L("Not enough memory.")) }
        var mp3 = [UInt8](repeating: 0, count: Int(Double(capacity) * 1.25) + 7200)
        let total = max(1, Double(endFrame - startFrame))

        do {
            while input.framePosition < endFrame {
                try Task.checkCancellation()
                let remaining = AVAudioFrameCount(endFrame - input.framePosition)
                try input.read(into: buffer, frameCount: min(capacity, remaining))
                if buffer.frameLength == 0 { break }
                let left = channelData[0]
                let right = channels > 1 ? channelData[1] : channelData[0]
                let written = lame_encode_buffer_ieee_float(lame, left, right, Int32(buffer.frameLength), &mp3, Int32(mp3.count))
                guard written >= 0 else { throw ToolError.failed(L("MP3 encoding failed.")) }
                handle.write(Data(mp3[0..<Int(written)]))
                progress(Double(input.framePosition - startFrame) / total)
            }
            let flushed = lame_encode_flush(lame, &mp3, Int32(mp3.count))
            if flushed > 0 { handle.write(Data(mp3[0..<Int(flushed)])) }

            // En-tête Xing/LAME : durée et recherche exactes dans les lecteurs (indispensable en VBR).
            var tag = [UInt8](repeating: 0, count: 2880)
            let tagSize = lame_get_lametag_frame(lame, &tag, tag.count)
            if tagSize > 0 && tagSize <= tag.count {
                try handle.seek(toOffset: 0)
                handle.write(Data(tag[0..<tagSize]))
            }
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }
}

/// Encodeur WebP basé sur libwebp.
enum WebPEncoder {
    static func write(_ image: CGImage, to url: URL, quality: Double = 0.82, lossless: Bool = false) throws {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        try pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ToolError.failed(L("Not enough memory."))
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        // libwebp attend des couleurs non prémultipliées.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Int(pixels[i + 3])
            guard a > 0, a < 255 else { continue }
            pixels[i] = UInt8(min(255, Int(pixels[i]) * 255 / a))
            pixels[i + 1] = UInt8(min(255, Int(pixels[i + 1]) * 255 / a))
            pixels[i + 2] = UInt8(min(255, Int(pixels[i + 2]) * 255 / a))
        }

        var output: UnsafeMutablePointer<UInt8>?
        let size = lossless
            ? WebPEncodeLosslessRGBA(pixels, Int32(w), Int32(h), Int32(w * 4), &output)
            : WebPEncodeRGBA(pixels, Int32(w), Int32(h), Int32(w * 4), Float(quality * 100), &output)
        guard size > 0, let output else { throw ToolError.failed(L("WebP encoding failed.")) }
        defer { WebPFree(output) }
        try Data(bytes: output, count: size).write(to: url)
    }
}
