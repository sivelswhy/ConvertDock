import AppKit

/// Petite fenêtre de saisie (mot de passe, texte de filigrane…) affichée avant l'exécution d'un outil.
@MainActor
enum TextPrompt {
    /// `title` et `message` sont déjà traduits.
    static func ask(_ title: String, message: String, secure: Bool = false) -> ToolParameters? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Cancel"))
        let field = secure ? NSSecureTextField() : NSTextField()
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        var parameters = ToolParameters()
        parameters.text = field.stringValue
        return parameters
    }

    static func password(_ url: URL) async -> ToolParameters? {
        ask(L("Password"), message: L("Enter the password for “%@”.", url.lastPathComponent), secure: true)
    }

    static func watermark(_ url: URL) async -> ToolParameters? {
        ask(L("Watermark"), message: L("Text to write on “%@”.", url.lastPathComponent))
    }
}
