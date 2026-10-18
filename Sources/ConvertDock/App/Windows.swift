import AppKit
import SwiftUI

/// Panneau flottant qui peut recevoir le clavier (pour la recherche).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Panneau d'actions en verre, affiché quand des fichiers sont déposés sur l'icône de l'app.
@MainActor
final class QuickPanelController: NSObject, NSWindowDelegate {
    static let shared = QuickPanelController()

    private let model = QuickPanelModel()
    private var panel: KeyablePanel?
    private var keyMonitor: Any?
    private var closeObserver: Task<Void, Never>?
    private var shownAt = Date.distantPast

    func show(_ urls: [URL]) {
        model.reset(with: urls)
        model.onClose = { [weak self] in self?.close() }
        let panel = panel ?? makePanel()
        self.panel = panel

        // Centré sur l'écran où se trouve le pointeur.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                                         y: visible.midY - panel.frame.height / 2 + visible.height * 0.06))
        }
        NSApp.activate()
        shownAt = Date()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        installKeyMonitor()
        watchForCompletion()
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        closeObserver?.cancel()
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
                                 styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self

        let glass = NSGlassEffectView()
        glass.cornerRadius = 30
        glass.style = .regular
        let hosting = NSHostingView(rootView: QuickPanelView(model: model))
        hosting.sizingOptions = []
        glass.contentView = hosting
        panel.contentView = glass
        return panel
    }

    /// Navigation clavier : ↑ ↓ pour choisir, ↩ pour lancer, Échap pour fermer.
    private func installKeyMonitor() {
        if keyMonitor != nil { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.keyCode == 53 { // Échap
                if let job = model.job, !job.isActive { model.job = nil } else if model.job == nil { close() }
                return nil
            }
            guard model.job == nil else { return event }
            switch event.keyCode {
            case 125: model.move(1); return nil          // ↓
            case 126: model.move(-1); return nil         // ↑
            case 36, 76: model.runSelected(); return nil // ↩
            default: return event
            }
        }
    }

    /// Ferme automatiquement le panneau à la fin si l'utilisateur l'a demandé.
    private func watchForCompletion() {
        closeObserver?.cancel()
        closeObserver = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, let job = model.job, case .succeeded = job.state else { continue }
                if UserDefaults.standard.bool(forKey: Preferences.closePanelWhenDone) {
                    try? await Task.sleep(for: .seconds(1.2))
                    if model.job === job { close() }
                }
                return
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Juste après l'ouverture, l'activation de l'app peut rendre une autre fenêtre active : on reprend le focus.
        if Date().timeIntervalSince(shownAt) < 1.5 {
            DispatchQueue.main.async { [weak self] in self?.panel?.makeKeyAndOrderFront(nil) }
            return
        }
        // Un clic ailleurs ferme le panneau, sauf pendant un traitement ou la découpe.
        guard let job = model.job else { close(); return }
        if !job.isActive { close() }
    }
}

/// Fenêtre principale, en verre, avec barre de titre transparente.
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "ConvertDock"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.setFrameAutosaveName("MainWindow")
            window.minSize = NSSize(width: 760, height: 560)

            let background = NSVisualEffectView()
            background.material = .underWindowBackground
            background.blendingMode = .behindWindow
            background.state = .active
            let hosting = NSHostingView(rootView: MainView())
            hosting.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: background.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            ])
            window.contentView = background
            if window.frame.origin == .zero { window.center() }
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = L("Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
