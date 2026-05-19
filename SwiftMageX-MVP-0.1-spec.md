# SwiftMageX — Technical Specification, MVP 0.1

| | |
|---|---|
| **Project** | SwiftMageX |
| **Document version** | 0.1 (MVP) |
| **Date** | May 18, 2026 |
| **Status** | Draft specification, ready for implementation |
| **Binaries** | `swiftmagex` (CLI; short alias `smx`), `swiftmagex-mcp` (MCP server) |

---

## 1. Overview and goals

SwiftMageX is a CLI tool for image generation and processing. Architecturally it is an **orchestrator, not an engine**: the tool does not load ML models into its own process — it calls an external API, and performs local raster operations (resize, text overlay) itself, without AI.

The goal of version 0.1 is a working, installable tool with three commands plus a Model Context Protocol server, validating the provider layer and the `RasterEngine` in practice. This is the foundation that later versions extend with editing, comics, local models, and asset generation.

**MVP principles:**

- Lean dependencies — exactly two external packages (`swift-argument-parser` and the MCP Swift SDK).
- Single platform — macOS only.
- Extensibility is expressed through protocols (`ImageProvider`, `RasterEngine`), but with one implementation each.
- Agent-friendly from day one — a structured `--json` mode in the CLI and a full MCP server.

---

## 2. Scope of version 0.1

### In scope

- `generate` command — image generation from a text prompt via the Gemini API.
- `resize` command — local resize / crop / format conversion, no AI.
- `text` command — text overlay onto an image, no AI.
- **MCP server** (`swiftmagex-mcp`) — exposes the three capabilities above as Model Context Protocol tools for AI agents.
- Provider layer with an `ImageProvider` protocol and one implementation — `GeminiProvider`.
- `RasterEngine` layer with a protocol and one implementation — `CoreImageRasterEngine`.
- Configuration via environment variables and CLI flags.
- Structured `--json` output and meaningful exit codes.
- Generation metadata (prompt, seed, model) embedded into the output file.

### Out of scope (deferred)

| Capability | Target version |
|---|---|
| `edit` command, inpainting, outpainting | 0.2 |
| Local models (Ollama, ComfyUI) | 0.2 |
| Asset packs (App Store icons / screenshots) | 0.2 |
| Result caching | 0.2 |
| Configuration file (`config.toml`) | 0.2 |
| Keychain-based key storage | 0.2 |
| Homebrew distribution | 0.2 |
| Comic pipeline, script generation | 0.3+ |
| Recipe files, `--enhance`, `--variations` | 0.2+ |
| Linux support | Not planned — macOS only |

The boundary is deliberate: anything beyond the three commands, one provider, and the MCP wrapper waits for later releases.

---

## 3. Technology stack

| Component | Choice | Rationale |
|---|---|---|
| Language | Swift 6.x | Single static binary; `swift-argument-parser`; full access to CoreImage/CoreText/ImageIO. |
| Platform | macOS 14+ | Single-platform MVP. No cross-platform abstraction overhead. |
| CLI framework | `swift-argument-parser` | Declarative subcommands, validation, generated help. |
| MCP server | MCP Swift SDK (`modelcontextprotocol/swift-sdk`) | Official SDK for exposing Model Context Protocol tools over stdio. |
| Networking | `Foundation.URLSession` | Native, async, zero dependency. macOS-only scope makes this an unconditional choice. |
| Raster operations | CoreImage / ImageIO / CoreText | Resize, text overlay, format I/O, metadata writing — all built in. |
| Logging | Internal `stderr` wrapper | No dependency. `swift-log` may be adopted in 0.2. |
| External AI provider | Gemini API (Nano Banana) | Native multimodal generation; default model `gemini-2.5-flash-image`. |

**External dependencies — exactly two.** `SwiftMageXKit` (the core library) has no external dependencies; networking is `URLSession`, raster work is system frameworks. The `swiftmagex` CLI adds `swift-argument-parser`; the `swiftmagex-mcp` server adds the MCP Swift SDK. Neither frontend depends on the other's dependency.

---

## 4. Architecture

Version 0.1 uses a reduced layered design. The CLI and the MCP server are two thin frontends over the same `SwiftMageXKit` library — no business logic is duplicated.

```
┌──────────────────────┐   ┌──────────────────────┐
│  swiftmagex (CLI)     │   │  swiftmagex-mcp      │  ← two thin frontends
│  generate·resize·text │   │  MCP server (stdio)  │
└──────────┬───────────┘   └──────────┬───────────┘
           │                          │
           └────────────┬─────────────┘
                        │
        ┌───────────────▼──────────────────┐
        │  SwiftMageXKit (core library)     │
        │  • request validation & assembly  │
        │  • result metadata                │
        └──────┬───────────────────┬────────┘
               │                   │
      ┌────────▼────────┐  ┌───────▼───────────┐
      │  ImageProvider  │  │  RasterEngine      │
      │  protocol       │  │  protocol          │
      │  └ GeminiProvid…│  │  └ CoreImageRast…  │
      └────────┬────────┘  └────────────────────┘
               │
      ┌────────▼────────┐
      │  Gemini API     │
      └─────────────────┘
```

**Layers:**

1. **Frontends** — `swiftmagex` (CLI) and `swiftmagex-mcp` (MCP server). Both only handle their interface concerns: argument parsing and output formatting for the CLI, the MCP protocol for the server. No business logic.
2. **Core** (`SwiftMageXKit`) — orchestration: validates inputs, assembles requests, invokes the provider or the raster engine, and builds the result.
3. **Provider layer** — the `ImageProvider` protocol with one implementation. The `resize` and `text` capabilities do not use a provider.
4. **Raster engine** — the `RasterEngine` protocol with one implementation. The `generate` capability uses it for post-processing (writing the file, optional resize of the result).

The `generate` capability uses both the provider and the raster engine. `resize` and `text` use only the raster engine.

---

## 5. Package structure

Three targets in a single `Package.swift`: the core library, the CLI executable, and the MCP server executable.

```
SwiftMageX/
├── Package.swift
├── README.md
├── Sources/
│   ├── SwiftMageXKit/
│   │   ├── Providers/
│   │   │   ├── ImageProvider.swift        — protocol + ProviderCapabilities
│   │   │   └── GeminiProvider.swift        — Gemini implementation
│   │   ├── Raster/
│   │   │   ├── RasterEngine.swift          — protocol
│   │   │   └── CoreImageRasterEngine.swift — CoreImage/ImageIO implementation
│   │   ├── Models/
│   │   │   ├── GenerationRequest.swift
│   │   │   ├── GeneratedImage.swift
│   │   │   ├── ImageSize.swift
│   │   │   └── ImageFormat.swift
│   │   ├── Net/
│   │   │   ├── HTTPClient.swift             — protocol (for testability)
│   │   │   └── URLSessionHTTPClient.swift   — implementation
│   │   ├── Config/
│   │   │   └── Configuration.swift          — environment variable reading
│   │   └── SwiftMageXError.swift
│   ├── swiftmagex/
│   │   ├── SwiftMageX.swift                 — root ParsableCommand
│   │   ├── GlobalOptions.swift              — --json, --verbose
│   │   ├── Commands/
│   │   │   ├── GenerateCommand.swift
│   │   │   ├── ResizeCommand.swift
│   │   │   └── TextCommand.swift
│   │   └── Output/
│   │       └── ResultPrinter.swift          — human / json formatting
│   └── swiftmagex-mcp/
│       ├── MCPServer.swift                  — server bootstrap, stdio transport
│       └── Tools/
│           ├── GenerateImageTool.swift
│           ├── ResizeImageTool.swift
│           └── OverlayTextTool.swift
└── Tests/
    └── SwiftMageXKitTests/
        ├── RasterEngineTests.swift
        ├── GeminiRequestTests.swift
        └── Mocks/
            ├── MockImageProvider.swift
            └── MockHTTPClient.swift
```

Root command:

```swift
@main
struct SwiftMageX: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftmagex",
        abstract: "Generate and process images from the terminal.",
        version: "0.1.0",
        subcommands: [GenerateCommand.self, ResizeCommand.self, TextCommand.self]
    )
}
```

---

## 6. CLI commands

Global options (available on every subcommand):

| Option | Purpose |
|---|---|
| `--json` | Structured output to stdout instead of human-readable text. |
| `--verbose` / `-v` | Diagnostic messages to stderr. |

### 6.1 `swiftmagex generate`

Generate an image from a text prompt.

```
swiftmagex generate <prompt> [options]
```

| Option | Type | Default | Purpose |
|---|---|---|---|
| `<prompt>` | positional | — | Text prompt (required). |
| `--output` / `-o` | path | `./` | Destination file or directory. |
| `--size` / `-s` | enum | `square` | `square`, `portrait`, `landscape`. Actual resolution depends on the model. |
| `--count` / `-n` | int | `1` | Number of variants to generate (1–4). |
| `--seed` | uint64 | — | Seed for reproducibility (see §12 — support is provider-dependent). |
| `--model` | string | `gemini-2.5-flash-image` | Gemini model identifier. |

Examples:

```
swiftmagex generate "neon-lit cyberpunk alley in the rain"
swiftmagex generate "minimalist app icon, fox head" -s square -o icon.png
swiftmagex generate "mountain landscape at dawn" -n 4 --json
```

### 6.2 `swiftmagex resize`

Local resize, crop, and format conversion. No AI is used; quota consumption is zero.

```
swiftmagex resize <input> [options]
```

| Option | Type | Default | Purpose |
|---|---|---|---|
| `<input>` | path | — | Source file (required). |
| `--width` / `-w` | int | — | Target width in pixels. |
| `--height` / `-h` | int | — | Target height in pixels. |
| `--fit` | enum | `contain` | `contain` (fit inside), `cover` (fill with crop), `fill` (stretch). |
| `--output` / `-o` | path | next to source | Destination file. |
| `--format` | enum | same as source | `png`, `jpeg`. |
| `--quality` | double | `0.9` | JPEG quality (0.0–1.0). |

At least one of `--width` / `--height` must be given. If only one is provided, the other is computed preserving aspect ratio.

```
swiftmagex resize photo.png -w 512 -h 512 --fit cover
swiftmagex resize banner.png -w 1200 --format jpeg --quality 0.8
```

### 6.3 `swiftmagex text`

Overlay text onto an image.

```
swiftmagex text <input> --text "<string>" [options]
```

| Option | Type | Default | Purpose |
|---|---|---|---|
| `<input>` | path | — | Source file (required). |
| `--text` | string | — | Text to overlay (required). |
| `--position` | enum | `bottom` | `top`, `center`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`. |
| `--font` | string | system | Font name. |
| `--font-size` | int | `48` | Point size. |
| `--color` | string | `#FFFFFF` | Text color (hex). |
| `--stroke` | string | — | Stroke color (hex); omitted means no stroke. |
| `--stroke-width` | double | `2.0` | Stroke width. |
| `--output` / `-o` | path | next to source | Destination file. |

Text is automatically wrapped to the available width and placed within a safe zone with edge padding.

```
swiftmagex text screenshot.png --text "Download on the App Store" --position bottom
swiftmagex text cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

---

## 7. MCP server

SwiftMageX ships a Model Context Protocol server, `swiftmagex-mcp`, so AI agents can use the same capabilities as tools. It is a separate target built on the MCP Swift SDK and depends on `SwiftMageXKit` — the same core as the CLI, with no logic duplication.

- **Transport:** stdio. The server is launched as a subprocess by an MCP client (for example, the Claude desktop app) according to that client's configuration. It takes no command-line arguments.
- **Registration:** the user adds `swiftmagex-mcp` and its environment (the API key) to their MCP client configuration.
- **API key:** read from the same environment variables as the CLI (§10); the MCP client passes the environment when spawning the process.

### Exposed tools

Three tools, mirroring the CLI commands. Their input schemas mirror the corresponding CLI flags.

| Tool | Key inputs | Result |
|---|---|---|
| `generate_image` | `prompt` (required), `size`, `count`, `seed`, `model` | Absolute path(s) and metadata as text; the generated image(s) also returned as MCP image content so the calling model can inspect the result. |
| `resize_image` | `input` (required), `width`, `height`, `fit`, `output`, `format`, `quality` | Absolute output path and metadata as text. |
| `overlay_text` | `input` (required), `text` (required), `position`, `font`, `font_size`, `color`, `stroke` | Absolute output path and metadata as text. |

- All tool results report **absolute file paths** — the calling agent does not know the server's working directory.
- Errors are returned as MCP tool errors, carrying the same semantic categories as the CLI exit codes (§13).
- Returning generated images inline as MCP image content lets an agent see what it produced. For `resize_image` and `overlay_text` the agent already supplied the input, so only the path and metadata are returned in 0.1.

---

## 8. Provider layer

### Protocol

```swift
public protocol ImageProvider: Sendable {
    var id: String { get }
    var capabilities: ProviderCapabilities { get }
    func generate(_ request: GenerationRequest) async throws -> [GeneratedImage]
}

public struct ProviderCapabilities: Sendable {
    public var supportsSeed: Bool
    public var maxBatchSize: Int
    public var supportedSizes: [ImageSize]
}
```

In 0.1 the protocol declares only `generate`. An `edit(_:)` method arrives in 0.2 — the protocol is designed for extension.

### Data models

```swift
public struct GenerationRequest: Sendable {
    public var prompt: String
    public var size: ImageSize
    public var count: Int
    public var seed: UInt64?
    public var model: String
}

public struct GeneratedImage: Sendable {
    public var data: Data
    public var format: ImageFormat
    public var prompt: String
    public var model: String
    public var seed: UInt64?
}
```

### GeminiProvider

The only implementation in 0.1.

- **Endpoint:** `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- **Authentication:** an `x-goog-api-key` header with the value from an environment variable.
- **Request:** a body carrying the text prompt in `contents`.
- **Response:** the image is returned as a base64 string in `candidates[].content.parts[].inlineData`. The provider decodes it into `Data`.
- **Default model:** `gemini-2.5-flash-image` (Nano Banana) — stable, supports generation. `--model` can select another (for example `gemini-3.1-flash-image-preview`); preview models are used at the caller's risk.
- **Multiple variants:** when `--count > 1`, the corresponding number of requests is issued, with exponential backoff between retries on a `429` response.

---

## 9. RasterEngine

Local pixel operations, no AI.

```swift
public protocol RasterEngine: Sendable {
    func load(from url: URL) throws -> RasterImage
    func resize(_ image: RasterImage, to spec: ResizeSpec) throws -> RasterImage
    func overlayText(_ image: RasterImage, _ spec: TextSpec) throws -> RasterImage
    func write(_ image: RasterImage,
               to url: URL,
               format: ImageFormat,
               quality: Double,
               metadata: ImageMetadata?) throws
}
```

`CoreImageRasterEngine` is the only implementation, built on CoreImage, CoreText, and ImageIO:

- Loading and saving via `ImageIO` (PNG, JPEG; HEIC/WebP reading comes for free).
- Resize and crop via CoreImage with `contain` / `cover` / `fill` modes.
- Text overlay via CoreText: line wrapping, stroke, safe-zone positioning.
- Writing metadata into the output file (PNG `tEXt` / EXIF) via `ImageIO`.

The protocol is kept (rather than a bare concrete type) for testability — it lets command logic be exercised against a test double.

---

## 10. Configuration and secrets

In 0.1, configuration is environment variables and CLI flags only. There is no configuration file.

| Variable | Required | Purpose |
|---|---|---|
| `SWIFTMAGEX_GEMINI_API_KEY` | for `generate` / `generate_image` | Gemini API key. |
| `GEMINI_API_KEY` | fallback | Used if the variable above is not set. |
| `SWIFTMAGEX_OUTPUT_DIR` | optional | Default output directory. |

The key is never logged or printed, including under `--verbose`. The `resize` and `text` capabilities do not require a key. The MCP server reads the key from the environment its client passes at spawn time. Keychain storage and a `config.toml` file are planned for 0.2.

---

## 11. Command execution flow

Using `generate` as the example:

1. The frontend (CLI or MCP tool) parses and validates inputs.
2. It reads the API key from the environment; if absent, a configuration error (exit code 4).
3. It assembles a `GenerationRequest` and passes it to `SwiftMageXKit`.
4. The core instantiates `GeminiProvider` and calls `generate(_:)`.
5. The provider performs the HTTP request(s), retries with backoff on `429`, and decodes the response into `[GeneratedImage]`.
6. The core writes each image to disk via `CoreImageRasterEngine`, embedding metadata.
7. The frontend returns the result: human-readable text or JSON for the CLI; structured content (paths, metadata, image data) for the MCP tool.

For `resize` / `text` steps 2–5 are skipped — the core works directly with the `RasterEngine`.

---

## 12. Output, file naming, metadata

**Naming.** If the output target is a directory (or unspecified), files are named with the pattern `swiftmagex_{timestamp}_{index}.{ext}`. If a specific file is given, it is used; with `--count > 1`, an index is appended.

**Metadata.** Each generated file embeds: prompt, model name, seed (if any), timestamp, and tool version. This makes every result self-documenting and reproducible.

**On `--seed`.** Seed support is provider-dependent and reflected in `ProviderCapabilities.supportsSeed`. If the provider does not accept a seed, the value is still written to metadata as recorded intent. Whether `gemini-2.5-flash-image` accepts a seed must be verified during implementation (see §17).

**JSON output.** Under `--json`, stdout contains a single object: status, the list of output files with absolute paths, the model and provider used, and — on error — code and message. Absolute paths are mandatory; this mirrors what the MCP tools return.

---

## 13. Error handling and exit codes

A unified error type:

```swift
public enum SwiftMageXError: Error {
    case invalidInput(String)
    case configuration(String)   // missing key, missing file, etc.
    case provider(String)        // API failure
    case raster(String)          // image processing failure
    case io(String)
}
```

Exit codes:

| Code | Meaning |
|---|---|
| `0` | Success. |
| `1` | Unexpected runtime error. |
| `2` | Invalid arguments or input. |
| `3` | Provider / API error (including quota exhaustion). |
| `4` | Configuration error (missing or invalid API key). |

On a `429` response, the provider performs up to 5 retries with exponential backoff (1 s start, doubling); once retries are exhausted, exit code 3 with a clear message. MCP tools map these same categories onto MCP tool errors.

---

## 14. Build, dependencies, distribution

**Dependencies in 0.1:** exactly two external packages — `swift-argument-parser` (CLI only) and the MCP Swift SDK (MCP server only). The core library has no external dependencies; networking is `URLSession`, logging is an internal wrapper.

**Build:**

```
swift build -c release
```

This produces both binaries: `swiftmagex` and `swiftmagex-mcp`.

**Distribution in 0.1:** building from source plus prebuilt macOS (arm64) binaries attached to the GitHub release. A Homebrew formula (`brew install`) is a 0.2 task.

---

## 15. Testing

| What | How |
|---|---|
| `RasterEngine` | Unit tests for resize, crop, and text overlay on reference inputs; verifying output dimensions and format. |
| Gemini request building | Unit test: `GenerationRequest` → a correct HTTP request body, with no real network calls (via `MockHTTPClient`). |
| Response parsing | Unit test decoding a fixed Gemini JSON response into `[GeneratedImage]`. |
| CLI logic | `MockImageProvider` (implements `ImageProvider` without network) — runs commands end to end without consuming quota. |
| MCP tools | The tool handlers run against `MockImageProvider`; tool input-schema validation is unit-tested. |
| Exit codes | Verifying error types map to the specified exit codes. |

Real integration calls to the Gemini API are not run in CI (cost, flakiness) — only manual checks and an optional separate test set behind a flag.

---

## 16. Work plan for 0.1

A suggested sequence — each step yields a verifiable result:

1. **Package skeleton.** `Package.swift`, three targets, the root command, subcommand stubs.
2. **RasterEngine + `resize`.** A fully local command — the first end-to-end result, no network or keys.
3. **`text`.** Text overlay on top of the working raster engine.
4. **Provider layer + GeminiProvider.** Protocols, data models, HTTP client, the Gemini implementation.
5. **`generate`.** Request assembly, response handling, file writing with metadata, retries.
6. **`--json` and exit codes.** Bring CLI output and termination in line with the spec.
7. **MCP server.** The `swiftmagex-mcp` target wrapping the proven core: three tools, stdio transport, error mapping.
8. **Tests and `README`.** The coverage from §15, plus installation and usage docs (including MCP client registration).
9. **Release 0.1.0.** Tag, build both binaries, GitHub release page.

---

## 17. Risks and open questions

| Risk / question | Note |
|---|---|
| API cost and limits | Image generation via the Gemini API is paid; the free tier was reduced in December 2025. Verify current pricing and limits on `ai.google.dev` before release. Cap `--count` / `count` at four by default. |
| Seed support by the model | Verify whether `gemini-2.5-flash-image` accepts a seed parameter. If not, in 0.1 `--seed` is only written to metadata. |
| Preview model instability | `gemini-3.1-flash-image-preview` is reachable via `--model` but, as a preview, may change. The default is deliberately the stable `gemini-2.5-flash-image`. |
| Gemini API changes | The endpoint and response format are isolated inside `GeminiProvider` — changes stay local. |
| MCP Swift SDK maturity | The SDK is relatively young; pin a specific version and isolate its use inside the `swiftmagex-mcp` target so an upgrade is contained. |
| Content moderation | Relies on the provider's moderation; moderation failures map to exit code 3 / an MCP tool error with a clear message. |
| macOS-only | A deliberate, permanent decision. CoreImage and `URLSession` are unconditional choices; no cross-platform abstraction is carried. |

---

## 18. Roadmap beyond 0.1

- **0.2** — the `edit` command (inpainting / outpainting); local models (Ollama, ComfyUI); asset packs for developers (App Store icons and screenshots); result caching; a configuration file; Keychain storage; Homebrew distribution.
- **0.3+** — the comic pipeline (script → panels → consistent characters via reference images); recipe files; `--enhance`.

---

*This document describes version 0.1 only. The full product vision and the rationale for architectural decisions live in the project's design materials.*
