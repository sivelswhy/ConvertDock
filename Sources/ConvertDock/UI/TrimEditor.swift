import AVKit

/// Fenêtre de découpe utilisant l'interface de trim native d'AVKit (celle de QuickTime Player).
@MainActor
enum TrimEditor {
    static func present(_ url: URL) async -> ToolParameters? {
        let asset = AVURLAsset(url: url)
        let hasVideo = (try? await asset.loadTracks(withMediaType: .video).isEmpty == false) ?? false
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)

        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = false

        let size = hasVideo ? NSSize(width: 820, height: 520) : NSSize(width: 640, height: 150)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        window.title = L("Trim “%@”", url.lastPathComponent)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        if hasVideo {
            window.backgroundColor = .black
            window.contentView = playerView
        } else {
            // Audio : la barre de trim flotte sur du verre.
            let glass = NSGlassEffectView()
            glass.cornerRadius = 0
            glass.contentView = playerView
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = glass
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // Attend que l'élément soit prêt avant de démarrer le trim.
        for _ in 0..<100 where item.status != .readyToPlay {
            if item.status == .failed { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard item.status == .readyToPlay, playerView.canBeginTrimming else {
            window.close()
            return nil
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<AVPlayerViewTrimResult, Never>) in
            playerView.beginTrimming { continuation.resume(returning: $0) }
        }
        player.pause()
        window.orderOut(nil)
        window.close()

        guard result == .okButton else { return nil }
        let duration = item.duration.isNumeric ? item.duration.seconds : nil
        let start = item.reversePlaybackEndTime.isNumeric ? item.reversePlaybackEndTime.seconds : 0
        let end = item.forwardPlaybackEndTime.isNumeric ? item.forwardPlaybackEndTime.seconds : duration
        return ToolParameters(trimStart: max(0, start), trimEnd: end)
    }
}
