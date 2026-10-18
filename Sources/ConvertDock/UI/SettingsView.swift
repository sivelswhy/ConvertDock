import SwiftUI

struct SettingsView: View {
    @AppStorage(OutputLocation.defaultsKey) private var location = OutputLocation.sameFolder.rawValue
    @AppStorage(Preferences.playSound) private var playSound = true
    @AppStorage(Preferences.revealWhenDone) private var revealWhenDone = false
    @AppStorage(Preferences.closePanelWhenDone) private var closePanelWhenDone = false
    @ViewState private var aliasMessage: String?

    var body: some View {
        Form {
            Section("Fichiers créés") {
                Picker("Enregistrer", selection: $location) {
                    ForEach(OutputLocation.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Afficher dans le Finder à la fin", isOn: $revealWhenDone)
                Toggle("Jouer un son à la fin", isOn: $playSound)
            }
            Section("Panneau rapide") {
                Toggle("Fermer le panneau dès que c'est terminé", isOn: $closePanelWhenDone)
                LabeledContent("Raccourci sur le Bureau") {
                    Button("Créer") { createDesktopAlias() }
                }
                if let aliasMessage {
                    Text(aliasMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Déposez n'importe quel fichier sur l'icône de ConvertDock (Dock ou Bureau) pour ouvrir le menu d'actions. Vous pouvez aussi faire clic droit › Services › « Convertir avec ConvertDock » dans le Finder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }

    private func createDesktopAlias() {
        do {
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let link = desktop.appendingPathComponent("ConvertDock")
            if FileManager.default.fileExists(atPath: link.path) {
                aliasMessage = "Un raccourci existe déjà sur le Bureau."
                return
            }
            let data = try Bundle.main.bundleURL.bookmarkData(options: .suitableForBookmarkFile)
            try URL.writeBookmarkData(data, to: link)
            aliasMessage = "Raccourci créé : déposez vos fichiers dessus."
        } catch {
            aliasMessage = error.localizedDescription
        }
    }
}
