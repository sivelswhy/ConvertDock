import SwiftUI

struct SettingsView: View {
    @AppStorage(OutputLocation.defaultsKey) private var location = OutputLocation.sameFolder.rawValue
    @AppStorage(Preferences.playSound) private var playSound = true
    @AppStorage(Preferences.revealWhenDone) private var revealWhenDone = false
    @AppStorage(Preferences.closePanelWhenDone) private var closePanelWhenDone = false
    @ViewState private var aliasMessage: String?

    var body: some View {
        Form {
            Section(L("Created files")) {
                Picker(L("Save to"), selection: $location) {
                    ForEach(OutputLocation.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle(L("Reveal in Finder when done"), isOn: $revealWhenDone)
                Toggle(L("Play a sound when done"), isOn: $playSound)
            }
            Section(L("Quick panel")) {
                Toggle(L("Close the panel when done"), isOn: $closePanelWhenDone)
                LabeledContent(L("Desktop shortcut")) {
                    Button(L("Create")) { createDesktopAlias() }
                }
                if let aliasMessage {
                    Text(aliasMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text(L("Drop any file on the ConvertDock icon (Dock or Desktop) to open the actions menu. You can also right-click › Services › “Convert with ConvertDock” in the Finder."))
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
                aliasMessage = L("A shortcut already exists on the Desktop.")
                return
            }
            let data = try Bundle.main.bundleURL.bookmarkData(options: .suitableForBookmarkFile)
            try URL.writeBookmarkData(data, to: link)
            aliasMessage = L("Shortcut created: drop your files on it.")
        } catch {
            aliasMessage = error.localizedDescription
        }
    }
}
