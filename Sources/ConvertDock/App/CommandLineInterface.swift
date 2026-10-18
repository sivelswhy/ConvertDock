import Foundation

/// Interface en ligne de commande, pratique pour les scripts et les tests.
@MainActor
enum CommandLineInterface {
    static func run(_ args: [String]) async -> Int32 {
        if args.first == "--list" {
            for tool in ToolRegistry.all {
                print("\(tool.id.padding(toLength: 22, withPad: " ", startingAt: 0)) \(tool.category.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)) \(tool.displayTitle)")
            }
            return 0
        }
        if args.first == "--l10n-keys" {
            // Clés affichées dynamiquement (titres d'outils, catégories), pour vérifier les traductions.
            let keys = ToolCategory.allCases.map(\.rawValue) + ToolRegistry.all.flatMap { [$0.title, $0.subtitle] }
            for key in NSOrderedSet(array: keys) { print(key) }
            return 0
        }
        if args.first == "--search", args.count > 1 {
            let result = SmartSearch.search(ToolRegistry.all, query: args[1...].joined(separator: " "))
            if let note = result.note { print("💡 \(note)") }
            for tool in result.tools { print("\(tool.id) — \(tool.displayTitle)") }
            return 0
        }
        var rest = Array(args.drop { $0 != "--run" }.dropFirst())
        guard let id = rest.first, let tool = ToolRegistry.all.first(where: { $0.id == id }) else {
            fputs(L("Unknown tool. Use --list to see the identifiers.") + "\n", stderr)
            return 2
        }
        rest.removeFirst()
        var parameters = ToolParameters()
        if let i = rest.firstIndex(of: "--trim"), i + 2 < rest.count {
            parameters.trimStart = Double(rest[i + 1])
            parameters.trimEnd = Double(rest[i + 2])
            rest.removeSubrange(i...(i + 2))
        }
        let urls = rest.map { URL(fileURLWithPath: $0).standardizedFileURL }
        guard tool.accepts(all: urls) else {
            fputs(L("“%@” does not accept these files.", tool.displayTitle) + "\n", stderr)
            return 2
        }
        let groups: [[URL]] = tool.combinesInputs ? [urls] : urls.map { [$0] }
        do {
            for group in groups {
                let context = JobContext(parameters: parameters) { _ in }
                for output in try await tool.run(group, context) { print(output.path) }
            }
            return 0
        } catch {
            fputs(L("Error: %@", error.localizedDescription) + "\n", stderr)
            return 1
        }
    }
}
