import ArgumentParser

/// The `swiftmagex` CLI entry point.
///
/// Routes into one of the subcommands per spec §6 (`composite`, `appstore`, and
/// `remove-bg` are post-0.1 local additions). All actual work lives in
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
            RemoveBackgroundCommand.self,
        ]
    )
}
