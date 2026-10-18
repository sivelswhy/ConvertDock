import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openedWithFiles = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        // Lancée en déposant un fichier sur l'icône : seul le panneau rapide s'affiche.
        if !openedWithFiles { MainWindowController.shared.show() }
    }

    /// Fichiers déposés sur l'icône (Dock, Bureau, Finder) ou « Ouvrir avec ».
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        openedWithFiles = true
        QuickPanelController.shared.show(files)
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
