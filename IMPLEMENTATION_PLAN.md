# SwiftMageX — Implementation Plan (post-skeleton)

> **Status: complete.** All nine milestones below shipped. The 0.1 MVP is
> feature-complete, the test suite is green, and v0.1.0 release notes live in
> `RELEASE_NOTES.md`. This document is preserved as a historical record of how
> the codebase was assembled — new work should reference the spec
> (`SwiftMageX-MVP-0.1-spec.md`) and `CLAUDE.md`, not this plan.
>
> Delivered milestones (one commit each):
>
> | Milestone | Commit | Title |
> |---|---|---|
> | 1 | `af0bbd9` | project skeleton |
> | 2 | `44373a9` | resize and raster engine |
> | 3 | `219f59f` | text overlay |
> | 4 | `5b60bb7` | provider layer + GeminiProvider |
> | 5 | `abf47f1` | generate command end-to-end |
> | 6 | `58fc938` | --json envelope and exit codes |
> | 7 | `80afd0d` | MCP server tool dispatch |
> | 8 | `4d5e8e5` | CLI tests, README polish, check.sh |
> | 9 | `849cb5f` | release prep — RELEASE_NOTES.md |

This document is the agent-facing companion to `SwiftMageX-MVP-0.1-spec.md`. The
spec is the **what**; this is the **how**, sequenced into milestones that each
end with a green build and a verifiable artifact.

Milestone 1 (project skeleton) is already complete — commit
`af0bbd9 chore: project skeleton (milestone 1)`. Every public type, every CLI
flag, every MCP tool schema is in place; the bodies are stubs marked
`// TODO(milestone N)`. Build and test are green.

> **Conventions for every milestone below**
>
> - Read the cited spec sections **before** touching code; the spec is authoritative.
> - Keep public API stable unless this document explicitly says to change it.
> - Do not add external dependencies. Do not relax `Sendable` / strict-concurrency.
> - Remove the `TODO(milestone N)` marker on each symbol as it lands.
> - Each milestone ends with `swift build` and `swift test` green and a commit
>   shaped like `feat: <milestone short name> (milestone N)`.

---

## Milestone 2 — `RasterEngine` and the `resize` command

**Spec:** §9 (RasterEngine), §6.2 (resize CLI), §12 (metadata, output paths).

### Goal

The first end-to-end command, fully local, no API key required:

```sh
swiftmagex resize photo.png -w 512 -h 512 --fit cover
swiftmagex resize banner.png -w 1200 --format jpeg --quality 0.8
```

### Files to touch

- `Sources/SwiftMageXKit/Raster/CoreImageRasterEngine.swift` — replace every stub.
- `Sources/SwiftMageXKit/Raster/RasterEngine.swift` — only if a small helper or
  computed property is genuinely needed by both `resize` and `text`. Avoid
  changes to the protocol shape; if you must, update the doc comment too.
- `Sources/swiftmagex/Commands/ResizeCommand.swift` — implement `run()`.
- `Sources/swiftmagex/Output/ResultPrinter.swift` — wire the human-text branch
  for success (full JSON branch is milestone 6, but emit minimal JSON now so
  the surface exists and the `--json` flag isn't a lie).
- `Tests/SwiftMageXKitTests/RasterEngineTests.swift` — replace the placeholder
  with real round-trip tests.

### Implementation notes

1. **Loading.** `ImageIO`'s `CGImageSourceCreateWithURL` is the right primitive.
   Reject unsupported types with `SwiftMageXError.raster("unsupported format: \(uti)")`.
   PNG / JPEG / HEIC / WebP read are free; that's worth a one-line doc comment.
2. **Source format detection.** When `--format` is omitted in `ResizeCommand`,
   derive the output `ImageFormat` from the input UTI, defaulting to PNG when
   the input is HEIC / WebP (those are read-only in 0.1 — write goes back to PNG
   or JPEG only). Surface this in `--verbose` diagnostics.
3. **Resize math.** CoreImage `CILanczosScaleTransform` produces good results;
   `CIAffineTransform` for the post-clip. Implement all three fit modes:
   - `contain` — preserve aspect ratio, scale to fit inside the target box.
     If only one of width/height is given, compute the other.
   - `cover` — preserve aspect ratio, scale to fill, then crop the overflow.
     Both width and height must be supplied (validate in `ResizeCommand`).
   - `fill` — scale freely, ignore aspect ratio. Both dimensions required.
4. **Single-dimension input.** If only `--width` is given, target height is
   `round(sourceHeight * width / sourceWidth)`, and `--fit` collapses to the
   `contain` behavior. Same logic for `--height` only. Reject `cover` / `fill`
   in `validate()` when one dimension is missing.
5. **Output URL resolution.** A tiny helper deserves to live in
   `SwiftMageXKit` so the same logic backs the MCP server in milestone 7.
   Suggested home: `Sources/SwiftMageXKit/Models/OutputPath.swift` (new file —
   add it to spec §5 in a comment if the team approves):
   - If `output` is a directory or omitted, name as
     `swiftmagex_{ISO-8601 compact}_{index}.{ext}` per §12.
   - Always return an **absolute** `URL` (use `.standardizedFileURL` after
     resolving against the current directory). The CLI and MCP both depend on
     this; absolute paths are mandatory per §7 and §12.
6. **Writing.** `CGImageDestinationCreateWithURL` with the matching UTI
   (`kUTTypePNG` / `kUTTypeJPEG`). For JPEG, set
   `kCGImageDestinationLossyCompressionQuality` from `quality`. Metadata
   writing is wired but trivial in milestone 2 — `ImageMetadata?` is nil for
   `resize` (no prompt/model context).
7. **Error mapping.** Use `SwiftMageXError.raster` for image-pipeline failures
   (decode, encode, unknown UTI). Use `SwiftMageXError.io` for FileManager /
   write-to-disk failures (permission denied, path is not a directory, etc.).
8. **Cleanup.** The CLI's `run()` should call into the kit synchronously — no
   `async` needed for `resize`. Use `try CoreImageRasterEngine().resize(...)`
   directly; the `AsyncParsableCommand` requirement only forces the function
   signature, not the body.

### Tests

Replace `testStubEngineThrowsNotImplementedForResize` with:

- `testResizeContainPreservesAspectRatio` — 100×200 → fit (50, 50) with
  `contain` produces 25×50.
- `testResizeCoverCropsOverflow` — 100×200 → (50, 50) with `cover` produces 50×50.
- `testResizeFillIgnoresAspectRatio` — 100×200 → (60, 40) with `fill` produces 60×40.
- `testResizeComputesMissingDimension` — width only, height preserved by ratio.
- `testRoundTripPNG` and `testRoundTripJPEG` — read → resize → write → re-read,
  asserting final dimensions and format via `CGImageSourceCopyTypeIdentifierOfSource`.

Reference inputs go in `Tests/SwiftMageXKitTests/Fixtures/` (add the directory;
keep PNGs small, ≤ 4 KB each). Generate them programmatically in a `setUp` if
that's easier than committing binaries.

### Definition of done

- [ ] `swift run swiftmagex resize Tests/.../fixture.png -w 256 -h 256 --fit cover`
      writes a 256×256 PNG to an absolute path and exits 0.
- [ ] `--json` emits a single object containing `status: "ok"` and an
      `outputs: [{path: <absolute>}]` array (full schema lands in milestone 6).
- [ ] All RasterEngine tests pass.
- [ ] No new SwiftPM dependency.

---

## Milestone 3 — The `text` command

**Spec:** §9 (RasterEngine.overlayText), §6.3 (text CLI).

### Goal

```sh
swiftmagex text screenshot.png --text "Download on the App Store" --position bottom
swiftmagex text cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

### Implementation notes

1. **Color parsing.** `TextSpec.color` and `strokeColor` arrive as `"#RRGGBB"`
   / `"#RRGGBBAA"`. Add a small `CGColor.init?(hexString:)` helper in
   `CoreImageRasterEngine` (private). Validate in `TextCommand.validate()` so
   bad input is `SwiftMageXError.invalidInput`, not a runtime raster failure.
2. **Layout.** Use CoreText (`CTFramesetter` + `CTFrame`). The safe-zone is a
   percentage of the image — start with 5% padding on every edge; constants
   should live as `private static let` on `CoreImageRasterEngine`.
3. **Wrapping.** Break by `\n` first, then word-wrap each line within the safe
   zone. CoreText's framesetter handles word wrap; you just provide the bound.
4. **Stroke.** `NSAttributedString` with `.strokeColor` / `.strokeWidth`
   attributes. A negative stroke width means "stroke + fill" — that's what we
   want; the spec says the stroke is in addition to the fill.
5. **Position anchoring.** Convert the seven positions to a 2D anchor:
   `top` = (0.5, 0.05), `bottom` = (0.5, 0.95), corners snap to (0.05, 0.05) etc.
   Vertical baseline math depends on whether you draw top-down or bottom-up;
   document the chosen convention in a `///` comment on the helper.
6. **Sendable.** `CGContext` is not Sendable; keep all CoreText work inside a
   single synchronous function. The engine is `Sendable` because it owns no
   mutable state.

### Tests

- `testTextOverlayWritesExpectedDimensions` — output dimensions == input dimensions.
- `testTextOverlayWithStrokeProducesDifferentBytesThanWithoutStroke` —
  smoke-test that the stroke parameter actually influences pixels.
- `testInvalidHexColorThrowsInvalidInput` — `"#ZZZ"` rejected pre-render.
- Add fixtures only if necessary; reuse milestone-2 fixtures where possible.

### Definition of done

- [ ] Round-trip with `--position bottom` and default font writes a PNG whose
      dimensions match the input.
- [ ] Stroke and non-stroke runs produce visibly different files (hash compare
      in test).
- [ ] Hex color validation rejects malformed input with exit code 2.

---

## Milestone 4 — Provider layer + `GeminiProvider`

**Spec:** §8 (provider layer + data models), §13 (429 retry policy), §17 (seed risk).

### Goal

Working Gemini API call that returns `[GeneratedImage]`. No CLI plumbing yet
(that's milestone 5); finish this milestone by passing a real request through
in a manual smoke test using `swift run` with a small driver in `Tests/` if
useful — or just by passing the new unit tests.

### Implementation notes

1. **Endpoint URL.**
   `https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent`.
   Build it with `URLComponents`, not string interpolation, so model names with
   unusual characters fail loudly rather than producing a bad URL.
2. **Headers.** `x-goog-api-key: <key>`, `Content-Type: application/json`.
   Never log the key, even in `--verbose`. Add a `redact(_ headers:)` helper if
   you're emitting headers to logs.
3. **Body.** Spec §8 says the body carries the prompt in `contents`. The
   minimal Gemini `generateContent` body for image generation is:
   ```json
   {
     "contents": [{"role": "user", "parts": [{"text": "<prompt>"}]}],
     "generationConfig": { "responseModalities": ["IMAGE"] }
   }
   ```
   Verify against the current Gemini docs at the moment of implementation —
   the schema for `gemini-2.5-flash-image` has shifted before.
4. **Response decoding.** Decode into a small internal `GeminiResponse`
   struct private to `GeminiProvider`. Image bytes live in
   `candidates[].content.parts[].inlineData.data` (base64) with `mimeType`.
   Map MIME to `ImageFormat`; reject unknown MIME types as
   `SwiftMageXError.provider`.
5. **Variants.** For `count > 1`, fan out N independent requests with a
   `withTaskGroup` (the API does not support a true batch in 0.1). Cap at the
   capability `maxBatchSize`. Preserve input order in the returned array.
6. **429 retry policy.** Up to 5 retries; backoff is 1 s, 2 s, 4 s, 8 s, 16 s.
   Apply only to 429 — any other 4xx is terminal. After exhaustion, throw
   `SwiftMageXError.provider("quota exhausted after 5 retries")`. Use
   `Task.sleep(for: .seconds(...))` and respect `Task.isCancelled`.
7. **Seed support.** Per §17, verify whether `gemini-2.5-flash-image` accepts
   a seed parameter at implementation time. If it does, set
   `capabilities.supportsSeed = true` and forward the value. If it doesn't,
   leave it `false` and record the seed only in metadata (milestone 5).
8. **Type isolation.** Every Gemini-specific type stays `private`/`fileprivate`
   inside `Providers/GeminiProvider.swift`. If a type needs to leak outward,
   the wire change is bigger than expected — stop and discuss before
   continuing.

### Tests

Replace `testStubProviderThrowsNotImplemented` with:

- `testGeminiRequestUsesCorrectEndpoint` — assert URL string against expected.
- `testGeminiRequestSetsAPIKeyHeader` — header present with the right value.
- `testGeminiRequestBodyIncludesPrompt` — decode body JSON and check `parts[0].text`.
- `testGeminiResponseDecodesBase64Image` — feed a 1×1 PNG base64 through
  `MockHTTPClient` and assert the returned `GeneratedImage.data` round-trips
  to the same bytes.
- `testGeminiRetriesOn429UpToFiveTimes` — `MockHTTPClient` returns 429 six
  times; verify total request count == 6 (1 + 5 retries) and the error is
  `.provider`.
- `testGeminiDoesNotRetryOn400` — a single 400 produces immediate failure.

### Definition of done

- [ ] Unit tests above all pass.
- [ ] A manual smoke test (developer-run, off CI) produces a real image into
      stdout-by-bytes or to disk via a tiny driver.
- [ ] No Gemini type appears outside `Providers/GeminiProvider.swift`.

---

## Milestone 5 — The `generate` command (end-to-end)

**Spec:** §6.1, §11 (execution flow), §12 (file naming, metadata).

### Goal

```sh
SWIFTMAGEX_GEMINI_API_KEY=… swiftmagex generate "neon-lit cyberpunk alley in the rain"
SWIFTMAGEX_GEMINI_API_KEY=… swiftmagex generate "mountain landscape" -n 4 --json
```

### Implementation notes

1. **Key resolution.** In `GenerateCommand.run()`, call
   `Configuration.resolvedAPIKey()`. If nil, throw
   `SwiftMageXError.configuration("missing SWIFTMAGEX_GEMINI_API_KEY")`. The
   CLI maps that to exit code 4 in milestone 6.
2. **Pipeline.**
   1. Build a `GenerationRequest` from parsed flags.
   2. `GeminiProvider(apiKey:httpClient:)` → `generate(_:)`.
   3. For each `GeneratedImage`, resolve the output URL (use the helper from
      milestone 2), assemble `ImageMetadata` (timestamp = `Date()`,
      `toolVersion` = `Configuration.toolVersion`, seed from the request even
      when the provider didn't honor it).
   4. `CoreImageRasterEngine().write(image, to:url, format:.png, quality:1.0, metadata:imageMetadata)`.
3. **Metadata embedding.** Use `ImageIO`:
   - PNG: write metadata as `tEXt` chunks via `CGImageDestinationAddImage`
     with a properties dictionary keyed under `kCGImagePropertyPNGDictionary`.
     Required entries: `Prompt`, `Model`, `Seed`, `Timestamp`, `ToolVersion`.
   - JPEG: write via `kCGImagePropertyExifDictionary` →
     `kCGImagePropertyExifUserComment` (a JSON blob of the same fields fits
     here; agents can re-parse it).
4. **Decode → re-encode caveat.** Gemini returns PNG-encoded bytes; you can
   stream them straight to disk without going through CoreImage, but only if
   you also need to embed metadata. The path of least resistance: decode to
   `CGImage`, then write through `CoreImageRasterEngine.write` so metadata is
   guaranteed.
5. **Output naming with `--count > 1`.** Per §12, append an index when a
   single filename was specified: `out.png` → `out_1.png`, `out_2.png`, …
   When the target is a directory, the `swiftmagex_{ts}_{index}.png` pattern
   already includes the index.

### Tests

Use `MockImageProvider` (no real network) to drive the CLI's pipeline in
unit tests at the **kit** level — add `Tests/SwiftMageXKitTests/GenerateFlowTests.swift`:

- `testGenerateWritesAllImagesToAbsolutePaths` — count=3 → three files on disk
  in a temp dir; every returned URL is absolute.
- `testGenerateEmbedsPromptAndModelInPNGMetadata` — re-open the written file
  with `CGImageSource` and assert the PNG dictionary contains the prompt.
- `testGenerateRequiresAPIKey` — when env vars are unset, the kit-level
  orchestrator throws `.configuration`.

(The CLI command itself is thin and a manual smoke test is enough.)

### Definition of done

- [ ] End-to-end run produces N files at absolute paths with embedded metadata.
- [ ] `--seed` is reflected in metadata even if the provider doesn't accept it.
- [ ] Missing API key → exit code 4 with a clear message.

---

## Milestone 6 — `--json` output and exit codes

**Spec:** §12 (JSON output schema), §13 (exit codes).

### Goal

Bring CLI output and termination into line with the spec for **every**
subcommand, including error paths.

### Implementation notes

1. **JSON schema.** Settle on:
   ```json
   {
     "status": "ok" | "error",
     "command": "generate" | "resize" | "text",
     "outputs": [{ "path": "/abs/path.png", "format": "png", "width": 1024, "height": 1024 }],
     "provider": "gemini",                       // generate only
     "model": "gemini-2.5-flash-image",          // generate only
     "error": { "code": 3, "category": "provider", "message": "…" }   // status=error only
   }
   ```
   Encode with `JSONEncoder(.sortedKeys, .prettyPrinted)`.
2. **Exit code mapping.** Already encoded as `SwiftMageXError.exitCode`. The
   CLI's `main` should catch `SwiftMageXError` at the top level, emit either
   the JSON error envelope (when `--json`) or a plain-text line, and call
   `exit(error.exitCode)`. ArgumentParser's `ExitCode` is fine for validation
   failures (exit 2 already matches `.invalidInput`).
3. **`--verbose`.** Routes through `ResultPrinter.diagnostic(_:)`. Confirm no
   path prints the API key — grep `apiKey` and `goog-api-key` before commit.
4. **Stderr vs stdout.** Diagnostics → stderr. Results (both JSON and human)
   → stdout. Errors under `--json` → stdout (so an agent can parse them);
   errors without `--json` → stderr.

### Tests

- `testErrorJSONEnvelopeForProviderFailure` — feed a `MockImageProvider` that
  throws `.provider`, run through the CLI's JSON renderer, assert schema.
- `testExitCodeForEachErrorCategory` — table-driven, one row per case of
  `SwiftMageXError`.

### Definition of done

- [ ] Every command returns the documented JSON schema under `--json`.
- [ ] Every error category exits with the spec-defined code.
- [ ] API key never appears in any output stream, including `--verbose`.

---

## Milestone 7 — MCP server (`swiftmagex-mcp`)

**Spec:** §7.

### Goal

The MCP tools dispatch to the same `SwiftMageXKit` code paths the CLI uses,
returning absolute paths plus — for `generate_image` — the image bytes as
MCP image content.

### Implementation notes

1. **Argument parsing.** Each tool's handler receives a
   `CallTool.Parameters` with `arguments: [String: Value]?`. Write a small
   typed extractor per tool that throws `MCPError.invalidParams` on missing
   required keys or type mismatches. Don't repeat this glue inline in
   `MCPServer.swift`; per-tool files (`Tools/*.swift`) own their parsing.
2. **Reusing kit logic.** The CLI's `run()` should not be the implementation
   site — extract the orchestration into a kit-level function such as:
   ```swift
   public enum SwiftMageXOrchestrator {
     public static func generate(_ request: GenerationRequest, output: URL?, environment: [String:String]) async throws -> [URL]
     public static func resize(input: URL, spec: ResizeSpec, output: URL?, format: ImageFormat?, quality: Double) throws -> URL
     public static func overlayText(input: URL, spec: TextSpec, output: URL?) throws -> URL
   }
   ```
   Both the CLI and the MCP tools call into this enum. Do this refactor as
   part of milestone 7; do **not** double-implement.
3. **Error mapping.** Catch `SwiftMageXError` inside each `CallTool` handler
   and return a `CallTool.Result(content: [.text(...)], isError: true)`. Use
   `MCPError.invalidParams` only for schema-level argument problems before
   the kit is called.
4. **Image content.** For `generate_image`, after writing each file, also
   include the bytes as `Tool.Content.image(data: base64, mimeType: ...)`
   so the calling model can inspect what was produced. For `resize_image` and
   `overlay_text` the agent already has the input, so return only `.text`
   with the absolute path and a short metadata summary.
5. **Lifecycle.** Current `MCPServer.swift` uses
   `server.start(transport:); await server.waitUntilCompleted()`. That's
   sufficient for 0.1. Skip the Swift Service Lifecycle integration; it would
   add a third dependency.

### Tests

- `testGenerateImageToolReturnsAbsolutePaths` — drive the handler with
  `MockImageProvider`; assert every path in the result is absolute.
- `testResizeImageToolMissingInputReturnsError` — input not provided; result
  has `isError: true` and a useful message.
- `testCallToolUnknownNameReturnsError` — sanity.

(Don't unit-test the SDK's protocol layer; only test handler behavior.)

### Definition of done

- [ ] All three tools execute against `MockImageProvider` end-to-end.
- [ ] Tool errors carry exit-code-equivalent semantic categories.
- [ ] No business logic lives in `Sources/swiftmagex-mcp/`; it all routes
      through `SwiftMageXOrchestrator`.

---

## Milestone 8 — Tests fill-in and README polish

**Spec:** §15.

### Goal

Get coverage to the level §15 calls for, finalize the README with MCP-client
registration instructions, and tag the work as release-ready.

### Tasks

1. **Coverage gaps.** After milestones 2–7, audit `Tests/` against §15:
   - RasterEngine: resize / crop / overlay on reference inputs. ✓ (m2/m3)
   - Gemini request building. ✓ (m4)
   - Response parsing. ✓ (m4)
   - CLI logic via `MockImageProvider`. (partial — add a small subset)
   - MCP tools via `MockImageProvider`. ✓ (m7)
   - Exit-code mapping. ✓ (m6)
2. **README.** Add:
   - A "Configure an MCP client" section with a JSON snippet for Claude
     Desktop. Use a placeholder for the binary path and `env` for the key.
   - A "Troubleshooting" stub with the three common categories (missing key,
     429 quota, unreadable input file).
   - A short note on what is *out of scope* in 0.1 with a link to spec §2.
3. **CI consideration.** Out of scope for 0.1 to set up CI, but add a
   `scripts/check.sh` (or just a `Makefile` target) that runs
   `swift build && swift test`, so a future CI hook is one line.

### Definition of done

- [ ] All §15 categories have at least one passing test.
- [ ] README documents installation, every command, and MCP registration.
- [ ] A single command (`swift test`) is the local gate.

---

## Milestone 9 — Release 0.1.0

**Spec:** §14 (distribution).

### Tasks

1. Bump nothing — `Configuration.toolVersion` is already `0.1.0`. Verify
   `swiftmagex --version` reports it.
2. `swift build -c release` produces both binaries; copy them out of
   `.build/arm64-apple-macosx/release/` and tag the release.
3. `git tag v0.1.0` + GitHub Release with the two binaries as assets. No
   Homebrew formula in 0.1 (that's 0.2).
4. Write a release note that links each delivered capability to its spec
   section.

### Definition of done

- [ ] `v0.1.0` tag pushed.
- [ ] GitHub release page lists both binaries.
- [ ] Spec §2 "in scope" items are all checked off.

---

## Cross-cutting reminders

- **Concurrency.** Strict concurrency is on. New async types crossing
  boundaries must be `Sendable`. Test mocks already model this with
  `OSAllocatedUnfairLock`.
- **Don't leak provider types.** Gemini-shaped types stay private to
  `Providers/GeminiProvider.swift`. The protocol is the boundary.
- **Absolute paths everywhere.** CLI JSON output and MCP tool results both
  report absolute file URLs (§7, §12). Use the milestone-2 helper.
- **API key hygiene.** Never log, never echo, never write to disk, never
  embed in metadata. Grep before committing.
- **Two dependencies, period.** Don't add `swift-log`, `swift-crypto`,
  `swift-collections`, etc., even transitively-tempted by an internal helper.
  If you reach for one, stop and ask.

---

## Quick reference: starting a new milestone

```sh
# pick up where the last agent left off
git log --oneline -10
swift build && swift test

# read the relevant spec sections cited under the milestone above

# work on a branch (optional but recommended)
git checkout -b milestone-N

# replace stubs, drop the TODO(milestone N) marker on each symbol you finish

# end-of-milestone gate
swift build && swift test
git commit -m "feat: <short description> (milestone N)"
```
