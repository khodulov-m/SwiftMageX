# SwiftMageX

## Post-0.1.0 — Image-to-image edit via Gemini

The first slice of the 0.2 `edit` work
([spec §3.1](SwiftMageX-MVP-0.1-spec.md), [§17](SwiftMageX-MVP-0.1-spec.md)) —
image-to-image and inpainting against the same Gemini `:generateContent`
endpoint `generate` already uses, with the source image (and optional mask)
sent as `inlineData` parts alongside the text prompt:

- New `swiftmagex edit <input> <prompt>` command / `edit_image` MCP tool.
  Required args: source image (PNG or JPEG) and a text instruction. Optional:
  `--mask` (grayscale/binary PNG/JPEG — white marks the region to edit),
  `--count 1–4`, `--seed`, `-o/--output`.
- Gemini-only: the CLI gates non-Gemini models in `validate()` (exit 2);
  `ImagenProvider` has a defensive guard that rejects any request carrying
  image bytes. Imagen's `:predict` shape has no inline-image slot.
- Wire-level changes are private to `GeminiProvider`: the request `parts[]`
  schema gained a sum-type entry (`{text}` *or* `{inlineData: {mimeType, data}}`)
  so each part encodes cleanly with no `null` keys. No new package dependency.
- `GenerationRequest` gained optional `referenceImage` / `referenceImageMimeType` /
  `mask` / `maskMimeType` fields with `nil` defaults — existing text-to-image
  call sites compile unchanged.
- Edited outputs carry the same `tEXt`/EXIF metadata as `generate` (prompt,
  model, seed, timestamp, tool version); the recorded prompt is the edit
  instruction.
- The MCP server now exposes nine tools.

## Post-0.1.0 — Saliency-aware smart crop

A new local raster command that crops to a user-supplied aspect ratio with the
crop window centered on the salient subject rather than the geometric centre:

- New `swiftmagex crop` command / `smart_crop` MCP tool. Takes `--aspect W:H`
  (e.g. `1:1`, `4:5`, `9:16`); no resize — pixels stay at source scale. Output
  format defaults to the source format (`--format png|jpeg` to override).
- Driven by Vision's on-device attention saliency
  (`VNGenerateAttentionBasedSaliencyImageRequest`). Same dep posture as
  `remove-bg`: a system framework, so the dependency budget (still exactly
  `swift-argument-parser` and `modelcontextprotocol/swift-sdk`) is untouched.
- `RasterEngine` gained `smartCrop(_:_:)`; the algorithm computes the largest
  `W:H` rect that fits in the source, positions it on the union centroid of
  the salient bounding boxes (Y-flipped from Vision's normalized coords),
  clamps to image bounds, and applies `CGImage.cropping(to:)`. When saliency
  yields no salient objects (rare; flat or uniform images), falls back to a
  center crop so the requested aspect ratio still holds.
- The MCP server now exposes eight tools.

## Post-0.1.0 — Bundled device frames

The `appstore` pipeline no longer requires a user-supplied bezel for common
devices:

- New `DeviceFrameCatalog` shipping the [PommePlate](https://github.com/ephread/PommePlate)
  iPhone 11 Pro Max / XS Max Space Grey bezel under [CC0 1.0](Sources/SwiftMageXKit/Resources/Frames/LICENSE-PommePlate.txt).
  The vendored PNG is a derivative — a clean rounded-rect screen cutout was
  punched into the upstream art so it works with `frameScreenshot`'s
  transparent-hole contract. See
  [Resources/Frames/ATTRIBUTION.md](Sources/SwiftMageXKit/Resources/Frames/ATTRIBUTION.md).
- `swiftmagex appstore`'s `--frame` flag now accepts a bundled frame id in
  addition to a path; omitting it auto-picks a bundled frame for the
  requested `--device` when one exists. `--list-frames` enumerates the
  bundled catalogue (plain or `--json`).
- `swiftmagex-mcp` exposes a new `list_frames` tool, and the
  `appstore_screenshots` tool's `frame` argument accepts the same ids.
- `frames.json` is the single source of truth for what's bundled — adding a
  new bezel is a JSON + PNG drop with no code change. Two helper scripts
  ship under `scripts/` for vendoring third-party art:
  `detect-screen-rect.swift` (finds the largest enclosed transparent region)
  and `punch-rounded-rect.swift` (derives a transparent cutout from art that
  renders the screen as a flat fill).

## Post-0.1.0 — App Store Connect screenshots

A first slice of the 0.2 "asset packs for developers" feature
([spec §2/§17](SwiftMageX-MVP-0.1-spec.md)) — preparing upload-ready App Store
Connect iPhone screenshots, entirely with local raster work (no API key):

- New `swiftmagex appstore` command / `appstore_screenshots` MCP tool: frames a
  screenshot inside a user-supplied iPhone bezel, scales it onto a background,
  overlays an optional caption, and writes one file per ASC iPhone size in a
  single run (`appstore_{device}_{w}x{h}.png`).
- New `swiftmagex composite` command / `composite_images` MCP tool: alpha-composite
  one image onto another with anchored position, scale, offset, and opacity. Used
  internally by `appstore` and exposed on its own.
- New `ASCDeviceCatalog` of iPhone screenshot slots — `iphone-6.9` (1290×2796,
  the default), `iphone-6.5` (1242×2688), `iphone-5.5` (1242×2208), plus `all` and
  an `--orientation` switch.
- `RasterEngine` gained `composite(_:onto:_:)` and `frameScreenshot(_:in:_:)`;
  the latter auto-detects the bezel's transparent screen cutout from its alpha
  channel (overridable with `--screen-rect`). `CoreImageRasterEngine` remains the
  only implementation; no new package dependencies, no bundled assets.
- The MCP server now exposes five tools.

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

Out of scope in this release — local providers (Ollama/ComfyUI), config file,
Keychain key storage, Homebrew distribution. (`edit`/inpainting was originally
listed here too; it now ships in a post-0.1 entry above.) See
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
