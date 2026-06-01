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

    /// Directory holding a content-addressed response cache for `generate`
    /// and `edit`. When set, identical inputs short-circuit the network call
    /// and replay the previously-recorded provider bytes. Heads-up: Gemini
    /// doesn't honor `--seed`, so a cache hit replaces intentional run-to-run
    /// variety with the same bytes every time — opt in deliberately.
    @Option(
        name: .customLong("cache-dir"),
        help: ArgumentHelp(
            "Cache directory for generate/edit responses. Identical inputs are served from this directory instead of calling the provider.",
            valueName: "path"
        )
    )
    var cacheDir: String?
}
