import ArgumentParser

/// The `swiftmagex` CLI entry point.
///
/// Routes into one of three subcommands per spec §6. All actual work lives in
/// `SwiftMageXKit`; this target is a thin frontend that parses arguments and
/// prints results.
@main
struct SwiftMageX: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftmagex",
        abstract: "Generate and process images from the terminal.",
        version: "0.1.0",
        subcommands: [
            GenerateCommand.self,
            ResizeCommand.self,
            TextCommand.self,
            CompositeCommand.self,
            AppStoreCommand.self,
        ]
    )
}
