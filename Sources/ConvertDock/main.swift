import AppKit

let app = NSApplication.shared
let arguments = CommandLine.arguments

if arguments.contains("--list") || arguments.contains("--run") || arguments.contains("--search") {
    // Mode ligne de commande : `ConvertDock --list` ou `ConvertDock --run <id-outil> [--trim début fin] fichiers…`
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in
        exit(await CommandLineInterface.run(Array(arguments.dropFirst())))
    }
} else {
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.setActivationPolicy(.regular)
}
app.run()
