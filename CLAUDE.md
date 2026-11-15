# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

SwiftMageX is a macOS-only (macOS 14+) CLI and MCP server for image generation (Gemini) and
on-device raster work (CoreImage, CoreText, ImageIO, Vision). `SwiftMageX-MVP-0.1-spec.md` is the
design blueprint (section numbers are cited below); `RELEASE_NOTES.md` and `git log` say what
changed since. The spec predates the current model catalog (see "Models"), so where it disagrees
with the code on models, the code wins.

## Build, test, run

```sh
swift build                               # debug build of both executables
swift build -c release                    # swiftmagex + swiftmagex-mcp
swift test                                # all three test targets
swift test --filter SwiftMageXKitTests.RasterEngineTests/testResizeContainPreservesAspectRatio
scripts/check.sh                          # build + test, the local gate before a PR
swift run swiftmagex <subcommand> ...     # CLI from sources
swift run swiftmagex-mcp                  # MCP server over stdio
```

- Generation needs `SWIFTMAGEX_GEMINI_API_KEY` (fallback `GEMINI_API_KEY`). `resize`, `text`,
  `composite`, `appstore`, `remove-bg`, `crop` and `icon` need no key. Never log or print the key,
  even under `--verbose`. Tests never call the network: use `MockImageProvider` / `MockHTTPClient`.
- Install a built binary with `install -m 755`, never `cp`: overwriting a running binary in place
  makes macOS kill the new one (exit 137). README has the steps.
- No CI; run `scripts/check.sh` before every PR. Releases: `v0.3.0` is the latest tag; the root
  `CLAUDE.md` has the tag and release-notes rules.
- User-facing changes touch `README.md` and the nine localized `README.*.md`; keep them in step.

## Architecture

One SwiftPM package, two thin frontends over one core:

- `SwiftMageXKit` (library): orchestration, `ImageProvider` and `RasterEngine` protocols, models,
  errors, config. **No external dependencies**; networking is `URLSession`.
- `swiftmagex` (CLI, `swift-argument-parser`): `generate`, `edit`, `resize`, `text`, `composite`,
  `appstore`, `remove-bg`, `crop`, `icon`; global `--json`, `--verbose`.
- `swiftmagex-mcp` (MCP over stdio, `modelcontextprotocol/swift-sdk`): ten tools mirroring the CLI
  (`generate_image`, `edit_image`, `resize_image`, `overlay_text`, `composite_images`,
  `appstore_screenshots`, `list_frames`, `remove_background`, `smart_crop`, `compose_icon`).

Rules that follow:

- Frontends own only their interface (argument parsing and output, or MCP protocol); business logic
  lives in the Kit. The frontends share no dependency; never pull one's dependency into the Kit.
- **Exactly two external packages** (argument-parser for the CLI, MCP SDK for the server). Do not add
  logging, JSON or HTTP crates. The MCP SDK is pinned `.upToNextMinor` because 0.x minors can
  break; bump it deliberately. SwiftPM resources (`Resources/Frames`) are not dependencies.
- One implementation per protocol (`GeminiProvider`, `CoreImageRasterEngine`); the protocols exist
  for testability. A new model is a new id in `ModelCatalog`, not a new provider, unless the wire
  shape differs. Keep Gemini wire types inside `Providers/`; the rest sees `GenerationRequest` /
  `GeneratedImage`.
- Swift 6 strict concurrency: types crossing async boundaries are `Sendable`.
- `generate` and `edit` use provider plus raster engine; `edit` sends the source, `--reference`
  images and the mask as `inlineData` parts of the same `:generateContent` call.

## Behaviour contracts

Check the spec section before changing any of these.

- Output paths are absolute in `--json` and in MCP results (the caller does not know the cwd). (§7, §12)
- Output into a directory is named `swiftmagex_{timestamp}_{index}.{ext}`; `--count > 1` with a file
  name appends an index. `--count` is 1-4, run as N parallel calls. (§6.1, §12)
- Every generated file embeds prompt, model, seed (if any), timestamp and tool version (PNG `tEXt` /
  EXIF). `--seed` is provider-dependent (`ProviderCapabilities.supportsSeed`); still record it. (§9)
- HTTP 429: up to 5 retries, backoff 1 s doubling, then exit code 3. (§13)
- Exit codes: 0 ok, 1 unexpected (raster, io), 2 invalid input, 3 provider/API, 4 config (missing
  key). MCP errors use the same categories (`category` strings are frozen, agents key off them).

## Models and Gemini API

- Default `gemini-3.1-flash-image`; alternates `gemini-3.1-flash-lite-image` and
  `gemini-3-pro-image`. **Only GA ids go in `ModelCatalog`**: a preview alias is retired later and
  the pass-through of unknown ids would hide it until Google switches it off. Unknown ids are passed
  to Gemini as is. Imagen is gone (retired 2026-08-17); an `imagen-*` id surfaces Google's 404 as
  exit 3.
- Endpoint `POST /v1beta/models/{model}:generateContent` with an `x-goog-api-key` header,
  `generationConfig.responseModalities: ["IMAGE"]` and an optional `imageConfig { aspectRatio,
  imageSize }`, omitted when neither is set. `GenerationRequest.aspectRatio` is the only ratio
  field; `--size` presets map into it. The image comes back base64 in
  `candidates[].content.parts[].inlineData`.
- **We validate ratio and resolution per model, Google does not**: the server checks only the union
  and bills unsupported pairs. `ImageModelDescriptor.aspectRatios` / `.resolutions` hold the
  per-model sets; `ModelCatalog.validateOutputOptions` rejects before the network (exit 2). Refresh
  the sets together with the catalog.

## Resources and Icon Composer

- `Sources/SwiftMageXKit/Resources/Frames/` holds bezel PNGs plus `frames.json` (`DeviceFrameCatalog`,
  declared `.copy` in `Package.swift`). A new bezel is a JSON and PNG drop; keep provenance and
  licence in `Frames/ATTRIBUTION.md`. `scripts/detect-screen-rect.swift` and
  `scripts/punch-rounded-rect.swift` help vendor new art. In tests use
  `DeviceFrameCatalog.resourceBundle`, not the test target's empty `.module`.
- `icon` builds an Icon Composer `.icon` package (`Sources/SwiftMageXKit/IconComposer/`).
  `IconComposerDocument` mirrors `icon.json`, reverse-engineered from real output: groups are listed
  front-first, `translation-in-points` is an offset from centred placement (y down), `scale`
  multiplies the layer's natural size at 1 px = 1 pt on a 1024-pt canvas; emit only verified keys.
  `--validate` runs `xcrun actool` and judges success by the produced `Assets.car`, because actool
  exits 0 even for broken packages. `--flat-preview` is an approximation (no glass, no squircle mask).
