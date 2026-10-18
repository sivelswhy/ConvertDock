import AppKit

/// Barre de menus construite en code (pas de storyboard dans un paquet SwiftPM).
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "À propos de ConvertDock", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Réglages…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu()
        NSApp.servicesMenu = services.submenu
        app.addItem(services)
        app.addItem(.separator())
        app.addItem(withTitle: "Masquer ConvertDock", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: "Masquer les autres", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Tout afficher", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quitter ConvertDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, title: "ConvertDock", to: main)

        let file = NSMenu(title: "Fichier")
        file.addItem(withTitle: "Ouvrir…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        file.addItem(withTitle: "Fermer", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(file, title: "Fichier", to: main)

        let edit = NSMenu(title: "Édition")
        edit.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Rétablir", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, title: "Édition", to: main)

        let window = NSMenu(title: "Fenêtre")
        window.addItem(withTitle: "ConvertDock", action: #selector(AppDelegate.showMainWindow(_:)), keyEquivalent: "1")
        window.addItem(withTitle: "Placer dans le Dock", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = window
        add(window, title: "Fenêtre", to: main)

        let help = NSMenu(title: "Aide")
        help.addItem(withTitle: "ConvertDock sur GitHub", action: #selector(AppDelegate.openGitHub(_:)), keyEquivalent: "")
        add(help, title: "Aide", to: main)

        return main
    }

    private static func add(_ menu: NSMenu, title: String, to main: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}
