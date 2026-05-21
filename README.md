# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

A macOS-only image generation and processing CLI. SwiftMageX is an
*orchestrator* — it calls the Google AI image API (Gemini or Imagen) for
generation and performs local raster operations (resize, text overlay) with
CoreImage / CoreText / ImageIO, all from a small Swift package with exactly
two external dependencies. The same core library backs a Model Context
Protocol server (`swiftmagex-mcp`) so AI agents can use the same capabilities
as tools.

See `SwiftMageX-MVP-0.1-spec.md` for the authoritative specification and
`RELEASE_NOTES.md` for what shipped in v0.1.0.

## Requirements

- macOS 14+ on Apple silicon (arm64)
- Swift 6.0+ toolchain (Xcode 16+) — only required to build from source
- A Google AI API key in `SWIFTMAGEX_GEMINI_API_KEY` (or `GEMINI_API_KEY`)
  for the `generate` command — used for both Gemini and Imagen models.
  `resize` and `text` need no key.

## Installation

### Prebuilt binary (recommended)

Grab `swiftmagex`, `swiftmagex-mcp`, and `SHA256SUMS` from the
[v0.1.0 release](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.1.0),
verify the checksums, then drop the binaries on your `PATH`:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.1.0
```

If macOS Gatekeeper quarantines the downloads, clear the flag:

```sh
xattr -d com.apple.quarantine /usr/local/bin/swiftmagex /usr/local/bin/swiftmagex-mcp
```

### Build from source

```sh
git clone https://github.com/khodulov-m/SwiftMageX.git
cd SwiftMageX
swift build -c release
# binaries land in .build/arm64-apple-macosx/release/
cp .build/arm64-apple-macosx/release/swiftmagex     /usr/local/bin/
cp .build/arm64-apple-macosx/release/swiftmagex-mcp /usr/local/bin/
```

### Run from source without installing

```sh
swift run swiftmagex <subcommand> …      # CLI
swift run swiftmagex-mcp                 # MCP server (stdio transport)
swift test                               # full test suite
scripts/check.sh                         # build + test in one step
```

### Configuration

Export the Gemini API key in your shell profile (only needed for `generate`):

```sh
export SWIFTMAGEX_GEMINI_API_KEY="…"   # preferred
# or, as a fallback the tool also reads:
export GEMINI_API_KEY="…"
```

Never embed the key in scripts you commit. The CLI never prints, logs, or
writes the key to disk — including under `--verbose` and inside output file
metadata.

## Quick manual

Three subcommands, all sharing the same global flags:

| Global flag | Effect |
|---|---|
| `--json` | Emit a structured JSON envelope to stdout instead of human-readable text. |
| `-v`, `--verbose` | Print diagnostic messages to stderr. Does **not** include the API key. |
| `--version` | Print `0.1.0` and exit. |
| `-h`, `--help` | Show help for the command. |

Output file paths are always **absolute** in `--json` output and in MCP tool
results — agents don't need to know the working directory.

### `swiftmagex generate` — text-to-image via Gemini or Imagen

```
swiftmagex generate <prompt> [options]
```

| Option | Default | Notes |
|---|---|---|
| `<prompt>` | — | Required positional argument. |
| `-o`, `--output <path>` | `./` | File or directory. If a directory, files are named `swiftmagex_{timestamp}_{index}.png`. |
| `-s`, `--size <square\|portrait\|landscape>` | `square` | Aspect-ratio hint. Actual resolution depends on the model. |
| `-n`, `--count <1–4>` | `1` | Number of variants. Each variant is a separate request. |
| `--seed <uint64>` | — | Recorded in metadata even when the provider ignores it. |
| `--model <id>` | `gemini-2.5-flash-image` | Built-ins: Gemini family (`gemini-2.5-flash-image`, `gemini-3-pro-image-preview`, `gemini-3.1-flash-image-preview`) and Imagen family (`imagen-4.0-generate-001`, `imagen-4.0-fast-generate-001`, `imagen-4.0-ultra-generate-001`). Unknown IDs route by `imagen-`/`gemini-` prefix. |

```sh
# Single image to the current directory
swiftmagex generate "neon-lit cyberpunk alley in the rain"

# Four landscape variants to a directory, structured output
swiftmagex generate "mountain landscape at dawn" -n 4 -s landscape -o ./out --json

# Reproducible seed (provider-dependent)
swiftmagex generate "minimalist app icon, fox head" --seed 42 -o icon.png
```

Example — the call below produced the image on the right (1024×1024 PNG from
`gemini-2.5-flash-image`):

```sh
swiftmagex generate "A simple red apple on a white background, test image" \
  -o apple.png
```

<img src="docs/images/example-generate-apple.png" alt="Generated red apple on a white background" width="320" />

Each output PNG carries the prompt, model, seed, timestamp, and tool version
in `tEXt` chunks (JPEG variants use the EXIF `UserComment` field).

### `swiftmagex resize` — local resize / crop / format conversion

```
swiftmagex resize <input> [options]
```

| Option | Default | Notes |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC, or WebP. Write is PNG / JPEG only. |
| `-w`, `--width <px>` | — | At least one of width / height is required. |
| `-h`, `--height <px>` | — | When only one is given, the other is computed by aspect ratio. |
| `--fit <contain\|cover\|fill>` | `contain` | `cover` and `fill` require both dimensions. |
| `-o`, `--output <path>` | sibling of source | Defaults next to the source file. |
| `--format <png\|jpeg>` | matches source | HEIC / WebP sources default to PNG. |
| `--quality <0.0–1.0>` | `0.9` | JPEG only. |

```sh
# Square thumbnail, crop overflow
swiftmagex resize photo.png -w 512 -h 512 --fit cover -o thumb.png

# 1200-wide banner, JPEG re-encode at 80 % quality
swiftmagex resize banner.png -w 1200 --format jpeg --quality 0.8

# Half-size, aspect ratio preserved (only width given)
swiftmagex resize cover.heic -w 1024 -o cover_1024.png
```

### `swiftmagex text` — text overlay

```
swiftmagex text <input> --text "<string>" [options]
```

| Option | Default | Notes |
|---|---|---|
| `<input>` | — | Image to draw on. |
| `--text <string>` | — | Required. `\n` produces a line break; long lines word-wrap. |
| `--position` | `bottom` | One of `top`, `center`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`. |
| `--font <name>` | system font | E.g. `"Helvetica-Bold"`. |
| `--font-size <pt>` | `48` | |
| `--color <hex>` | `#FFFFFF` | `#RRGGBB` or `#RRGGBBAA`. |
| `--stroke <hex>` | — | Omit for no stroke. |
| `--stroke-width <pt>` | `2.0` | Only used when `--stroke` is set. |
| `-o`, `--output <path>` | sibling of source | |

```sh
swiftmagex text screenshot.png --text "Download on the App Store" --position bottom
swiftmagex text cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

### JSON output schema

Every command emits the same envelope under `--json`. Keys are sorted; nil
fields are omitted entirely (no `null` placeholders).

Success:

```json
{
  "command": "generate",
  "model": "gemini-2.5-flash-image",
  "outputs": [
    { "format": "png", "height": 1024, "path": "/abs/out/swiftmagex_…_1.png", "width": 1024 }
  ],
  "provider": "gemini",
  "status": "ok"
}
```

Error (`resize` and `text` omit `provider` / `model`):

```json
{
  "command": "generate",
  "error": { "category": "configuration", "code": 4, "message": "missing SWIFTMAGEX_GEMINI_API_KEY" },
  "status": "error"
}
```

Stream conventions: results → **stdout**; diagnostics (`--verbose`) → **stderr**.
Error JSON is also written to stdout under `--json` so an agent can parse it
in one place.

### Exit codes

| Code | Meaning | Example |
|---|---|---|
| `0` | Success | — |
| `1` | Unexpected / raster / I/O failure | input file unreadable, encoder failure |
| `2` | Invalid input | bad `--fit` combo, malformed hex color, `--count` out of 1–4 |
| `3` | Provider / API failure | Gemini 5xx, `429` after 5 retries |
| `4` | Configuration | missing `SWIFTMAGEX_GEMINI_API_KEY` |

429 retry policy: up to 5 retries with exponential backoff 1 s → 2 s → 4 s → 8 s → 16 s.

## MCP server

`swiftmagex-mcp` exposes three tools — `generate_image`, `resize_image`,
`overlay_text` — over stdio. Tool arguments mirror the CLI flags above; tool
results report absolute file paths so the calling agent doesn't need to know
the server's working directory. `generate_image` additionally returns the
image bytes as MCP `image` content so the calling model can inspect what was
produced.

### Configure Claude Code

Claude Code registers MCP servers via `claude mcp add`. Inside the repo
where you want SwiftMageX available, run:

```sh
claude mcp add swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

To make it available in every Claude Code session on this machine, use the
user scope:

```sh
claude mcp add -s user swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

Inspect what's registered with `claude mcp list` or `claude mcp get swiftmagex`,
and remove it with `claude mcp remove swiftmagex`. Stdio is the default
transport — no `--transport` flag needed.

### Configure Claude Desktop

Add an entry to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "swiftmagex": {
      "command": "/usr/local/bin/swiftmagex-mcp",
      "env": {
        "SWIFTMAGEX_GEMINI_API_KEY": "your-key-here"
      }
    }
  }
}
```

The `env` block scopes the API key to this server only — it never lands on
disk in the client's general environment.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Configuration error: missing SWIFTMAGEX_GEMINI_API_KEY` (exit 4) | No API key in the environment when running `generate` or invoking `generate_image`. | Export `SWIFTMAGEX_GEMINI_API_KEY` (or the fallback `GEMINI_API_KEY`) — or, for MCP, add it to the client's `env` block as shown above. |
| `Provider error: quota exhausted after 5 retries` (exit 3) | Gemini returned `429` on every attempt in the backoff window (1 s → 16 s). | Wait for quota to refill, switch projects, or run again later. The backoff schedule is fixed; see spec §13. |
| `I/O error: input file not found: /…/foo.png` (exit 1) | The path passed to `resize` / `text` (or `resize_image` / `overlay_text`) doesn't exist or isn't readable. | Pass an absolute path, verify permissions, or check that the file format is one of PNG / JPEG / HEIC / WebP (write is PNG / JPEG only). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | Gatekeeper quarantine on a downloaded binary. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex` (and the same for `swiftmagex-mcp`). |

## Scope and status

This is the 0.1 MVP — three commands, two Google AI image providers
(Gemini and Imagen), one MCP server. Anything outside that boundary is
deferred; see spec
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
for the full out-of-scope list (edit / inpainting, local providers, Homebrew
distribution, config file, Keychain, …).

## License

TBD.
