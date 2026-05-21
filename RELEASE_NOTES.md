# SwiftMageX

## Post-0.1.0 — Image model switching

Added a second provider so `--model` (and the MCP `model` argument) can target
both Google AI image families with one binary:

- New `ImagenProvider` speaks the Imagen `:predict` shape; the existing
  `GeminiProvider` keeps speaking `:generateContent`.
- New `ModelCatalog` is the single source of truth for built-in model IDs and
  family routing; `SwiftMageXOrchestrator.makeProvider(for:apiKey:)` dispatches
  on it. Unknown IDs fall back to the `imagen-`/`gemini-` prefix.
- Built-in model list:
  - Gemini: `gemini-2.5-flash-image` (default), `gemini-3-pro-image-preview`,
    `gemini-3.1-flash-image-preview`.
  - Imagen: `imagen-4.0-generate-001`, `imagen-4.0-fast-generate-001`,
    `imagen-4.0-ultra-generate-001`.
- MCP `generate_image` schema gained an `enum` of supported models so clients
  can render a dropdown. CLI `--model` help lists the same set.
- Imagen multi-image is one `:predict` call with `sampleCount: count` (Gemini
  still fans out N parallel calls). `imagen-*-ultra-*` caps `sampleCount` at 1
  server-side — overrun surfaces as the standard `[provider]` error.
- Same `SWIFTMAGEX_GEMINI_API_KEY` / `GEMINI_API_KEY` works for both families;
  same 429 backoff (1 s → 16 s, ×5) and same exit codes apply.

This is a divergence from spec §8 (originally Gemini-only) — the spec stays
frozen as the 0.1 blueprint; see CLAUDE.md for the updated provider section.

# v0.1.0

First release of the 0.1 MVP — three CLI commands, one Gemini provider, and an
MCP server that exposes the same capabilities to AI agents. macOS arm64 only.

## Highlights

| Capability | Spec section |
|---|---|
| `swiftmagex generate` — image generation from a text prompt via Gemini | [§6.1](SwiftMageX-MVP-0.1-spec.md#61-swiftmagex-generate) |
| `swiftmagex resize` — local resize / crop / format conversion (no AI) | [§6.2](SwiftMageX-MVP-0.1-spec.md#62-swiftmagex-resize) |
| `swiftmagex text` — text overlay with stroke, wrap, and 7 positions | [§6.3](SwiftMageX-MVP-0.1-spec.md#63-swiftmagex-text) |
| `swiftmagex-mcp` — MCP server exposing `generate_image`, `resize_image`, `overlay_text` over stdio | [§7](SwiftMageX-MVP-0.1-spec.md#7-mcp-server) |
| `GeminiProvider` — `URLSession`-based client with 429 retry (1 s → 16 s, ×5) | [§8](SwiftMageX-MVP-0.1-spec.md#8-provider-layer), [§13](SwiftMageX-MVP-0.1-spec.md#13-error-handling-and-exit-codes) |
| `CoreImageRasterEngine` — Lanczos resize, CoreText overlay, ImageIO encode | [§9](SwiftMageX-MVP-0.1-spec.md#9-rasterengine) |
| Configuration via `SWIFTMAGEX_GEMINI_API_KEY` / `GEMINI_API_KEY` | [§10](SwiftMageX-MVP-0.1-spec.md#10-configuration-and-secrets) |
| Absolute-path output, indexed file naming, embedded PNG/JPEG metadata (prompt, model, seed, timestamp, tool version) | [§12](SwiftMageX-MVP-0.1-spec.md#12-output-file-naming-metadata) |
| Structured `--json` envelope and exit codes (0/1/2/3/4) | [§12](SwiftMageX-MVP-0.1-spec.md#12-output-file-naming-metadata), [§13](SwiftMageX-MVP-0.1-spec.md#13-error-handling-and-exit-codes) |

Out of scope in this release — `edit`/inpainting, local providers (Ollama/ComfyUI),
config file, Keychain key storage, Homebrew distribution. See
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01).

## Install

Download the binaries from the release assets, then:

```sh
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.1.0
```

To verify the downloaded files match the published checksums:

```sh
shasum -a 256 -c SHA256SUMS
```

Or build from source:

```sh
swift build -c release
```

## Requirements

- macOS 14+ on Apple silicon (arm64).
- Swift 6.0+ toolchain to build from source.
- A Gemini API key in `SWIFTMAGEX_GEMINI_API_KEY` (or `GEMINI_API_KEY`) for
  `generate`. `resize` and `text` need no key.

## Assets

- `swiftmagex` — CLI
- `swiftmagex-mcp` — MCP server (stdio transport)
- `SHA256SUMS` — checksums for both binaries
