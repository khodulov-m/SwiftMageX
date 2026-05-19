# SwiftMageX

A macOS-only image generation and processing CLI. SwiftMageX is an
*orchestrator* — it calls the Gemini API for generation and performs local
raster operations (resize, text overlay) with CoreImage / CoreText / ImageIO,
all from a small Swift package with exactly two external dependencies. The
same core library backs a Model Context Protocol server (`swiftmagex-mcp`) so
AI agents can use the same capabilities as tools.

See `SwiftMageX-MVP-0.1-spec.md` for the authoritative specification.

## Status

This repository currently contains the **project skeleton** (milestone 1 of
the work plan in spec §16). The architecture, public types, CLI surface, and
MCP tool schemas are in place; command bodies are stubbed and will be
implemented in subsequent milestones.

## Requirements

- macOS 14+
- Swift 6.0+ toolchain (Xcode 16+)
- A Gemini API key in `SWIFTMAGEX_GEMINI_API_KEY` (or `GEMINI_API_KEY`) for
  generation; not required for `resize` or `text`.

## Build

```sh
swift build                              # debug build of both binaries
swift build -c release                   # release build of swiftmagex + swiftmagex-mcp
swift run swiftmagex <subcommand> …      # run the CLI from sources
swift run swiftmagex-mcp                 # run the MCP server (stdio transport)
swift test                               # run the SwiftMageXKitTests suite
```

## Commands

```
swiftmagex generate <prompt> [--output …] [--size …] [--count …] [--seed …] [--model …]
swiftmagex resize   <input>  [--width …] [--height …] [--fit …] [--output …] [--format …] [--quality …]
swiftmagex text     <input>  --text "…" [--position …] [--font …] [--font-size …] [--color …] [--stroke …]
```

Every subcommand supports `--json` (structured output) and `--verbose`
(diagnostics to stderr).

## MCP server

`swiftmagex-mcp` exposes three tools — `generate_image`, `resize_image`,
`overlay_text` — over stdio. Register it in your MCP client's configuration
and pass the API key via the client's environment.

## License

TBD.
