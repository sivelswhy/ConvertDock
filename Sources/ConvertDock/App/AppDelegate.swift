import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launched = false
    private var pendingFiles: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        launched = true
        // Indexation Spotlight des outils, après l'affichage pour ne pas retarder le lancement.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SpotlightIndex.refreshIfNeeded() }
        if pendingFiles.isEmpty {
            MainWindowController.shared.show()
        } else {
            // Lancée en déposant un fichier sur l'icône : seul le panneau rapide s'affiche,
            // une fois l'app réellement active (sinon le panneau ne peut pas prendre le focus).
            let files = pendingFiles
            pendingFiles = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                QuickPanelController.shared.show(files)
            }
        }
    }

    /// Fichiers déposés sur l'icône (Dock, Bureau, Finder) ou « Ouvrir avec ».
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        if launched {
            QuickPanelController.shared.show(files)
        } else {
            pendingFiles += files
        }
    }

    /// Résultat choisi dans Spotlight (outil ou « Rechercher dans l'app »).
    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        SpotlightIndex.handle(userActivity)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowController.shared.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Service Finder « Convertir avec ConvertDock »

    @objc func convertFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        QuickPanelController.shared.show(urls)
    }

    // MARK: Menu

    @objc func showMainWindow(_ sender: Any?) { MainWindowController.shared.show() }
    @objc func showSettings(_ sender: Any?) { SettingsWindowController.shared.show() }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        NSApp.activate()
        if panel.runModal() == .OK { QuickPanelController.shared.show(panel.urls) }
    }

    @objc func openGitHub(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/sivelswhy/ConvertDock")!)
    }
}
