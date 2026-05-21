# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

SwiftMageX is an image generation/processing CLI (macOS-only). The 0.1 MVP is **feature-complete** — all nine milestones in `IMPLEMENTATION_PLAN.md` have shipped, the test suite is green, and `RELEASE_NOTES.md` maps each delivered capability to its spec section. The spec (`SwiftMageX-MVP-0.1-spec.md`) is still the authoritative blueprint; consult it before designing anything, and any divergence needs an explicit reason. `IMPLEMENTATION_PLAN.md` is now historical — useful for context on how the codebase was built, not for new work.

## Build / test / run

```sh
swift build                              # debug build of both binaries
swift build -c release                   # release build (produces swiftmagex + swiftmagex-mcp)
swift run swiftmagex <subcommand> …      # run the CLI from sources
swift run swiftmagex-mcp                 # run the MCP server (stdio transport)
swift test                               # run SwiftMageXKitTests
swift test --filter SwiftMageXKitTests.RasterEngineTests/testResizeContain   # single test
```

Generation requires `SWIFTMAGEX_GEMINI_API_KEY` (or fallback `GEMINI_API_KEY`) in the environment. `resize` and `text` need no key. Never log or print the key, even under `--verbose`.

## Architecture — the load-bearing shape

Three SwiftPM targets in one package; two thin frontends over one core library. The shape matters because it's the project's main constraint:

- **`SwiftMageXKit`** (library) — pure orchestration. **No external dependencies.** Networking is `URLSession`; raster work is CoreImage / CoreText / ImageIO. Defines the `ImageProvider` and `RasterEngine` protocols, request/response models, errors, and config.
- **`swiftmagex`** (executable) — CLI frontend. Depends on `SwiftMageXKit` + `swift-argument-parser`. Subcommands: `generate`, `resize`, `text`. Global flags: `--json`, `--verbose`.
- **`swiftmagex-mcp`** (executable) — MCP server frontend over stdio. Depends on `SwiftMageXKit` + the MCP Swift SDK. Exposes three tools (`generate_image`, `resize_image`, `overlay_text`) that mirror the CLI commands.

Frontends own *only* their interface concern (argparsing/output, or MCP protocol). All business logic lives in the Kit. The two frontends share no dependency with each other — keep it that way; don't introduce code in one that pulls the other's dependency into the Kit.

`generate` uses both `ImageProvider` (network) and `RasterEngine` (write file + embed metadata). `resize` and `text` use only `RasterEngine`.

### Protocols are abstractions for testability, not for plurality (yet)

In 0.1 each protocol has exactly **one** implementation (`GeminiProvider`, `CoreImageRasterEngine`). The protocols exist so command logic can be exercised against `MockImageProvider` / `MockHTTPClient` without burning Gemini quota. Don't add speculative second implementations; the spec defers Ollama/ComfyUI to 0.2.

### Dependency budget is a hard rule

**Exactly two external packages**: `swift-argument-parser` (CLI only) and `modelcontextprotocol/swift-sdk` (MCP server only). The Kit itself must stay dependency-free. The MCP SDK is pinned with `.upToNextMinor(from: "0.12.1")` because pre-1.0 minor bumps may break — patch updates only; bump deliberately. Don't add a logging crate, a JSON crate, an HTTP crate, etc.

### Swift 6 strict concurrency is on

`swift-tools-version: 6.0` enables strict concurrency by default. The Kit's data models (`GenerationRequest`, `GeneratedImage`, `ImageSize`, `ImageFormat`, `ProviderCapabilities`) are declared `Sendable` in the spec; both protocols (`ImageProvider`, `RasterEngine`) require `Sendable` conformance. New types crossing async boundaries must be `Sendable` too.

## Behavior contracts to preserve

These are easy to get subtly wrong if you're modifying the code. Cross-check against the cited spec section before touching anything in the relevant area.

- **Output paths are always absolute** in `--json` output and in MCP tool results — the calling agent doesn't know the cwd. (§7, §12)
- **File naming** when output is a directory: `swiftmagex_{timestamp}_{index}.{ext}`. With `--count > 1` and a specific filename, an index is appended. (§12)
- **Metadata embedded into each generated file**: prompt, model, seed (if any), timestamp, tool version. PNG `tEXt` / EXIF via ImageIO. (§9, §12)
- **`--seed` is provider-dependent.** Reflected in `ProviderCapabilities.supportsSeed`. If the provider doesn't accept it, still write it to metadata as recorded intent. (§12)
- **429 retry policy**: up to 5 retries, exponential backoff starting at 1 s, doubling. After exhaustion → exit code 3. (§13)
- **Exit codes**: 0 success, 1 unexpected, 2 invalid input, 3 provider/API, 4 config (missing key). MCP tool errors must map to the same semantic categories. (§13)
- **`--count` cap**: 1–4. (§6.1, §17)
- **Default model**: `gemini-2.5-flash-image` (stable). `gemini-3.1-flash-image-preview` is reachable via `--model` but is preview-quality. (§8)

## Gemini API specifics

- Endpoint: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- Auth header: `x-goog-api-key`
- Response: image is base64 in `candidates[].content.parts[].inlineData` — decode to `Data` inside `GeminiProvider`.
- All Gemini-shaped code stays inside `GeminiProvider` so API changes are local. Don't leak Gemini types out of `Providers/`.
