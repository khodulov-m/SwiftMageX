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
- **`swiftmagex`** (executable) — CLI frontend. Depends on `SwiftMageXKit` + `swift-argument-parser`. Subcommands: `generate`, `edit`, `resize`, `text`, `composite`, `appstore`, `remove-bg`, `crop` (`edit` plus the last four are post-0.1). Global flags: `--json`, `--verbose`.
- **`swiftmagex-mcp`** (executable) — MCP server frontend over stdio. Depends on `SwiftMageXKit` + the MCP Swift SDK. Exposes nine tools (`generate_image`, `edit_image`, `resize_image`, `overlay_text`, `composite_images`, `appstore_screenshots`, `list_frames`, `remove_background`, `smart_crop`) that mirror the CLI commands; `list_frames` is the discovery counterpart to `appstore_screenshots`'s bundled-bezel ids.

Frontends own *only* their interface concern (argparsing/output, or MCP protocol). All business logic lives in the Kit. The two frontends share no dependency with each other — keep it that way; don't introduce code in one that pulls the other's dependency into the Kit.

`generate` and `edit` use both `ImageProvider` (network) and `RasterEngine` (write file + embed metadata). `resize`, `text`, `composite`, `appstore`, `remove-bg`, and `crop` use only `RasterEngine` — no API key. `edit` is post-0.1 and Gemini-only: the source image, any additional `--reference` images, and an optional mask ride along as `inlineData` parts inside the same `:generateContent` call `generate` uses, so no new endpoint, no new dependency. The CLI gates non-Gemini models at `validate()` (exit 2); `ImagenProvider` has a defensive guard that rejects any request carrying image bytes. Multi-image lives entirely in the request model — `GenerationRequest.referenceImages: [ReferenceImage]` — so the provider just iterates and appends parts; adding more references is a list grow, not a code change. `appstore` (post-0.1) is the App Store Connect screenshot pipeline: frame a screenshot in a device bezel (a user-supplied path **or** a bundled frame id from `DeviceFrameCatalog`; auto-picked when the requested device has bundled art) → composite onto a background → optional caption → batch-resize to ASC iPhone sizes from `ASCDeviceCatalog`.

### Protocols are abstractions for testability — keep additions concrete

`RasterEngine` still has exactly one implementation (`CoreImageRasterEngine`) — it just grew more methods (`resize`, `overlayText`, `composite`, `frameScreenshot`, `removeBackground`, `smartCrop`, `load`, `write`). `removeBackground` is backed by Vision's on-device foreground segmentation (`VNGenerateForegroundInstanceMaskRequest`, macOS 14+); `smartCrop` is backed by Vision's on-device attention saliency (`VNGenerateAttentionBasedSaliencyImageRequest`). Both are system frameworks, so the dependency budget is untouched. `ImageProvider` now has two: `GeminiProvider` (`:generateContent`) and `ImagenProvider` (`:predict`). Both Google AI shapes share host + auth + retry policy but differ enough in request/response that a single class would be all branches. Routing between them lives in `ModelCatalog` (model id → family) and `SwiftMageXOrchestrator.makeProvider(for:apiKey:)` — add a new model id to the catalog, not a new provider, unless the wire shape genuinely differs. The protocols still exist primarily for testability against `MockImageProvider` / `MockHTTPClient`; the spec defers Ollama/ComfyUI to 0.2.

### Dependency budget is a hard rule

**Exactly two external packages**: `swift-argument-parser` (CLI only) and `modelcontextprotocol/swift-sdk` (MCP server only). The Kit itself must stay dependency-free. The MCP SDK is pinned with `.upToNextMinor(from: "0.12.1")` because pre-1.0 minor bumps may break — patch updates only; bump deliberately. Don't add a logging crate, a JSON crate, an HTTP crate, etc.

### Kit ships SwiftPM resources

`Sources/SwiftMageXKit/Resources/Frames/` carries device bezel PNGs + a `frames.json` manifest, surfaced through `DeviceFrameCatalog`. `Package.swift` declares them with `.copy("Resources/Frames")`. **This is not a dependency** — SwiftPM resources are a build feature, not a third-party package; the dep-budget rule still holds. The catalog is intentionally decoupled from `ASCDeviceCatalog` so one device id can have zero, one, or many bundled frames (colour variants, alternate eras). Adding a new bezel is a JSON + PNG drop with no code change. Two helper scripts live under `scripts/` for vendoring: `detect-screen-rect.swift` (find the largest enclosed transparent region in a candidate bezel) and `punch-rounded-rect.swift` (derive a clean cutout from third-party art that renders the screen as a flat fill rather than a transparent hole — PommePlate's iPhone art is the bundled example). `Bundle.module` is per-target, so tests reach the Kit's bundle via `DeviceFrameCatalog.resourceBundle` (the test target's own `.module` is empty). Provenance / licence metadata for bundled art lives in `Resources/Frames/ATTRIBUTION.md`; preserve it when adding new entries.

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
- **Default model**: `gemini-2.5-flash-image` (stable). Built-in alternates listed in `ModelCatalog.all` — Gemini family (`gemini-3-pro-image-preview`, `gemini-3.1-flash-image-preview`) and Imagen family (`imagen-4.0-generate-001`, `imagen-4.0-fast-generate-001`, `imagen-4.0-ultra-generate-001`). Unknown ids route by `imagen-`/`gemini-` prefix. (§8, post-0.1)

## Google AI image API specifics

Both providers hit `generativelanguage.googleapis.com` with the same `x-goog-api-key` header and the same 429 backoff (1 s → 16 s, ×5). What differs is the per-call shape — keep each shape isolated inside its provider so API changes stay local.

### Gemini family (`GeminiProvider`)

- Endpoint: `POST /v1beta/models/{model}:generateContent`
- Request: `contents: [{role:"user", parts:[{text}]}], generationConfig: { responseModalities: ["IMAGE"] }`
- Response: base64 image in `candidates[].content.parts[].inlineData` — decode to `Data` inside `GeminiProvider`.
- Multi-image: `--count > 1` is N parallel calls (the API takes one image per call).

### Imagen family (`ImagenProvider`)

- Endpoint: `POST /v1beta/models/{model}:predict`
- Request: `instances: [{prompt}], parameters: { sampleCount, aspectRatio }`. `aspectRatio` is `"1:1"` / `"9:16"` / `"16:9"` derived from `ImageSize`.
- Response: base64 images in `predictions[].bytesBase64Encoded` (one prediction per `sampleCount`).
- Multi-image: a single `:predict` call with `sampleCount: count`. `imagen-*-ultra-*` caps `sampleCount` at 1 server-side; `ImagenProvider` rejects `count > 1` for ultra up front as `invalidInput` (exit 2) — no network round-trip — so the server-side HTTP 400 is never reached.

Don't leak Gemini- or Imagen-shaped types out of `Providers/`; the orchestrator and frontends only see `GenerationRequest` / `GeneratedImage`.
