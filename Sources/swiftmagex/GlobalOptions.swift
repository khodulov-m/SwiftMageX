import ArgumentParser

/// Flags that apply to every subcommand (spec §6).
///
/// Subcommands embed this with `@OptionGroup` so the shared surface lives in
/// exactly one place.
struct GlobalOptions: ParsableArguments {
    /// Emit structured JSON to stdout instead of human-readable text.
    @Flag(name: .long, help: "Emit structured JSON to stdout instead of human-readable text.")
    var json: Bool = false

    /// Print diagnostic messages to stderr.
    @Flag(name: [.short, .long], help: "Print diagnostic messages to stderr.")
    var verbose: Bool = false
}
