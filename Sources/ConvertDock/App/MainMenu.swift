import AppKit

/// Barre de menus construite en code (pas de storyboard dans un paquet SwiftPM).
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: L("About ConvertDock"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: L("Settings…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        let services = NSMenuItem(title: L("Services"), action: nil, keyEquivalent: "")
        services.submenu = NSMenu()
        NSApp.servicesMenu = services.submenu
        app.addItem(services)
        app.addItem(.separator())
        app.addItem(withTitle: L("Hide ConvertDock"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: L("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: L("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: L("Quit ConvertDock"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, title: "ConvertDock", to: main)

        let file = NSMenu(title: L("File"))
        file.addItem(withTitle: L("Open…"), action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        file.addItem(withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(file, title: L("File"), to: main)

        let edit = NSMenu(title: L("Edit"))
        edit.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, title: L("Edit"), to: main)

        let window = NSMenu(title: L("Window"))
        window.addItem(withTitle: "ConvertDock", action: #selector(AppDelegate.showMainWindow(_:)), keyEquivalent: "1")
        window.addItem(withTitle: L("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = window
        add(window, title: L("Window"), to: main)

        let help = NSMenu(title: L("Help"))
        help.addItem(withTitle: L("ConvertDock on GitHub"), action: #selector(AppDelegate.openGitHub(_:)), keyEquivalent: "")
        add(help, title: L("Help"), to: main)

        return main
    }

    private static func add(_ menu: NSMenu, title: String, to main: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}
