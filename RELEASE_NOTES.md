# SwiftMageX

# v0.2.0

Everything that landed after the 0.1 MVP, rolled into one release. The
detailed entries below (each headed "Post-0.1.0 — …") are the changelog for
this version; they are kept as written when each capability shipped.

## Highlights

- `swiftmagex edit` — image-to-image, multi-image composition (repeatable
  `--reference`), and mask-based inpainting via Gemini; `edit_image` MCP tool.
- `swiftmagex appstore` — App Store Connect screenshot pipeline (bezel
  framing, background, caption, ASC iPhone sizes), with a bundled CC0 iPhone
  bezel and a `list_frames` discovery tool.
- `swiftmagex composite`, `remove-bg` (Vision foreground segmentation), and
  `crop` (Vision attention saliency) — all local, no API key.
- Imagen model family support (`imagen-4.0-*`) alongside Gemini via
  `ModelCatalog` routing; MCP `generate_image` exposes the model enum.
- Opt-in local response cache for `generate` / `edit` via `--cache-dir`.
- The MCP server now exposes nine tools.
- License: the project is now released under the MIT License (see `LICENSE`).

## Install

Download the binaries from the release assets, then:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.2.0
```

Or build from source:

```sh
swift build -c release
```

## Requirements

- macOS 14+ on Apple silicon (arm64).
- Swift 6.0+ toolchain to build from source.
- A Google AI API key in `SWIFTMAGEX_GEMINI_API_KEY` (or `GEMINI_API_KEY`)
  for `generate` / `edit` — used for both Gemini and Imagen models. All
  other commands are local and need no key.

## Assets

- `swiftmagex` — CLI
- `swiftmagex-mcp` — MCP server (stdio transport)
- `SHA256SUMS` — checksums for both binaries

## Post-0.2.0 — Icon Composer `.icon` packages (unreleased)

`swiftmagex icon` / MCP `compose_icon`: assemble an Apple Icon Composer
`.icon` package (the layered Liquid Glass app-icon format, iOS 26+ /
macOS 26+) from prepared layer images. Fully local, no API key.

- Layers listed bottom-to-top, each with optional `name`, `glass=false`,
  `scale`, `dx`/`dy` (points from centered placement on the 1024-pt canvas),
  solid `fill` tint, and 1-based `group` (contiguous, max 4 layers per
  group — Icon Composer's limit). The emitted `icon.json` mirrors documents
  produced by Icon Composer itself (verified against real output: groups
  front-first, `translation-in-points` as a center offset, `srgb:` color
  strings).
- `--fill solid:#HEX | auto:#HEX` icon background (`auto:` maps to Icon
  Composer's `automatic-gradient`).
- PNG layers are copied into `Assets/` byte-for-byte; JPEG/HEIC/WebP are
  re-encoded to PNG. The package is staged in a temp directory and moved
  into place; `--overwrite` replaces an existing package atomically.
- `--flat-preview` writes a flat 1024×1024 PNG composite (stacking only —
  no Liquid Glass, no squircle mask) for READMEs and non-Xcode consumers;
  the MCP tool returns it as `image` content.
- `--validate` compile-checks the finished package with Xcode's `actool`
  (the same step Xcode runs at build time). Success is detected by the
  produced `Assets.car`, since actool exits 0 even for broken packages.
  Missing actool → exit 4 (configuration); failed compile → exit 2.
- The MCP server now exposes ten tools.

## Post-0.1.0 — Local response cache for `generate` / `edit`

A content-addressed cache that short-circuits the Gemini/Imagen network call
when the same request comes in twice. Opt-in via a single CLI flag; the rest
of the pipeline (output paths, embedded metadata, JSON envelope) is
unchanged on a hit:

- New `--cache-dir <path>` global flag wired into `generate` and `edit`. When
  set, identical requests replay previously-recorded provider bytes from the
  given directory instead of calling the API; the output file is still
  written with fresh `tEXt`/EXIF metadata (timestamp, tool version) so
  downstream commands see no behavioural difference.
- Cache key is SHA-256 over a canonical JSON of `(model, prompt, size,
  count, seed)` plus the SHA-256 of every `referenceImages[]` byte payload
  and the mask bytes — different reference images / different mask hashes
  to a different key even when the prompt is identical.
- On-disk layout is one subdirectory per key: `meta.json` (count,
  createdAt, toolVersion, per-image format) alongside raw provider bytes
  (`0.png`, `1.png`, …). Writes stage into a `<key>.tmp.<uuid>` directory
  and rename into place atomically; an existing entry for the same key is
  left alone because content addressing guarantees its bytes satisfy any
  caller of the same key.
- `JSONResultEnvelope.Output` gains an optional `"cached": true|false`
  field, emitted only when `--cache-dir` was set. Plain mode is unchanged;
  `--verbose` prints `cache hit: <path>` per replayed image.
- `WrittenImage.wasCached` is the kit-level surface; `SwiftMageXOrchestrator`
  exposes a new `cache: ResponseCache?` parameter on `generate` / `edit`
  (default `nil`, so the MCP frontend and other callers stay source-compatible).
- Cache I/O is **best-effort** — a missing or corrupt entry, an unwritable
  directory, or a parse failure all degrade to a normal network call rather
  than aborting the command (verified by `ResponseCacheTests` + new
  `GenerateFlowTests` / `EditFlowTests` cache cases).
- Behavioural caveat documented in `--help` and the README: Gemini does not
  honor `--seed`, so identical requests are *meant* to vary across calls.
  A cache hit turns that intentional non-determinism into "same bytes every
  time" — which is why the cache is strictly opt-in. No new package
  dependency (SHA-256 comes from `CryptoKit`, a system framework).

## Post-0.1.0 — Image-to-image / multi-image edit via Gemini

The first slice of the 0.2 `edit` work
([spec §3.1](SwiftMageX-MVP-0.1-spec.md), [§17](SwiftMageX-MVP-0.1-spec.md)) —
image-to-image, multi-image composition, and inpainting against the same
Gemini `:generateContent` endpoint `generate` already uses, with every
attached image sent as an `inlineData` part alongside the text prompt:

- New `swiftmagex edit <input> <prompt>` command / `edit_image` MCP tool.
  Required args: primary source image (PNG or JPEG) and a text instruction.
  Optional: `--reference <path>` (repeatable — each adds another inline
  image part the prompt can compose against), `--mask` (grayscale/binary
  PNG/JPEG — white marks the region to edit on the primary input),
  `--count 1–4`, `--seed`, `-o/--output`. The MCP tool exposes `references`
  as an array.
- Gemini-only: the CLI gates non-Gemini models in `validate()` (exit 2);
  `ImagenProvider` has a defensive guard that rejects any request carrying
  image bytes. Imagen's `:predict` shape has no inline-image slot.
- Wire-level changes are private to `GeminiProvider`: the request `parts[]`
  schema gained a sum-type entry (`{text}` *or* `{inlineData: {mimeType, data}}`)
  so each part encodes cleanly with no `null` keys; the provider iterates
  `referenceImages` and appends one part per image. No new package dependency.
- `GenerationRequest` gained `referenceImages: [ReferenceImage]` (typed
  pairing of bytes + MIME) and optional `mask` / `maskMimeType` fields with
  empty / nil defaults — existing text-to-image call sites compile unchanged.
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
