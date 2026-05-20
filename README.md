# SwiftMageX

A macOS-only image generation and processing CLI. SwiftMageX is an
*orchestrator* — it calls the Gemini API for generation and performs local
raster operations (resize, text overlay) with CoreImage / CoreText / ImageIO,
all from a small Swift package with exactly two external dependencies. The
same core library backs a Model Context Protocol server (`swiftmagex-mcp`) so
AI agents can use the same capabilities as tools.

See `SwiftMageX-MVP-0.1-spec.md` for the authoritative specification.

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
swift test                               # run all test targets
scripts/check.sh                         # build + test in one step
```

## Commands

```
swiftmagex generate <prompt> [--output …] [--size …] [--count …] [--seed …] [--model …]
swiftmagex resize   <input>  [--width …] [--height …] [--fit …] [--output …] [--format …] [--quality …]
swiftmagex text     <input>  --text "…" [--position …] [--font …] [--font-size …] [--color …] [--stroke …]
```

Every subcommand supports `--json` (structured output) and `--verbose`
(diagnostics to stderr). Output paths in `--json` output and MCP tool results
are always absolute.

### Examples

```sh
swiftmagex generate "neon-lit cyberpunk alley in the rain" -n 2 --json
swiftmagex resize  photo.png -w 512 -h 512 --fit cover -o thumb.png
swiftmagex text    cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

## MCP server

`swiftmagex-mcp` exposes three tools — `generate_image`, `resize_image`,
`overlay_text` — over stdio. Tool results report absolute file paths so the
calling agent doesn't need to know the server's working directory.

### Configure an MCP client (Claude Desktop)

Add an entry to your client's MCP configuration. For Claude Desktop, this is
`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "swiftmagex": {
      "command": "/absolute/path/to/swiftmagex-mcp",
      "env": {
        "SWIFTMAGEX_GEMINI_API_KEY": "your-key-here"
      }
    }
  }
}
```

Use the release binary path (`.build/arm64-apple-macosx/release/swiftmagex-mcp`
after `swift build -c release`, or the binary you copied to `/usr/local/bin`
or similar). The `env` block scopes the API key to this server only — it
never lands on disk in the client's general environment.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Configuration error: missing SWIFTMAGEX_GEMINI_API_KEY` (exit 4) | No API key in the environment when running `generate` or invoking `generate_image`. | Export `SWIFTMAGEX_GEMINI_API_KEY` (or the fallback `GEMINI_API_KEY`) — or, for MCP, add it to the client's `env` block as shown above. |
| `Provider error: quota exhausted after 5 retries` (exit 3) | Gemini returned `429` on every attempt in the backoff window (1 s → 16 s). | Wait for quota to refill, switch projects, or run again later. The backoff schedule is fixed; see spec §13. |
| `I/O error: input file not found: /…/foo.png` (exit 1) | The path passed to `resize` / `text` (or `resize_image` / `overlay_text`) doesn't exist or isn't readable. | Pass an absolute path, verify permissions, or check that the file format is one of PNG / JPEG / HEIC / WebP (write is PNG / JPEG only). |

## Scope and status

This is the 0.1 MVP — three commands, one provider (Gemini), one MCP server.
Anything outside that boundary is deferred; see spec
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
for the full out-of-scope list (edit / inpainting, local providers, Homebrew
distribution, config file, Keychain, …).

## License

TBD.
