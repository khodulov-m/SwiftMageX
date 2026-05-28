import Foundation
import MCP
import SwiftMageXKit

/// Entry point for `swiftmagex-mcp` — an MCP server over stdio (spec §7).
///
/// Boots an MCP `Server`, registers the tools that mirror the CLI commands,
/// and routes each `CallTool` request through ``ToolHandlers``.
/// The handlers themselves delegate to ``SwiftMageXOrchestrator``, so the MCP
/// server adds no business logic of its own.
@main
struct MCPServerMain {
    static func main() async throws {
        let server = Server(
            name: "swiftmagex-mcp",
            version: Configuration.toolVersion,
            instructions: """
            SwiftMageX MCP server. Provides eight tools mirroring the CLI:
            generate_image, resize_image, overlay_text, composite_images,
            appstore_screenshots, list_frames, remove_background, and
            smart_crop. Tool results return absolute file paths because the
            calling agent does not know the server's working directory.
            """,
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: SwiftMageXTools.all)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                switch params.name {
                case GenerateImageTool.name:
                    let provider = try makeImageProvider(for: params.arguments)
                    return try await ToolHandlers.generate(
                        arguments: params.arguments,
                        provider: provider
                    )
                case ResizeImageTool.name:
                    return try ToolHandlers.resize(arguments: params.arguments)
                case OverlayTextTool.name:
                    return try ToolHandlers.overlayText(arguments: params.arguments)
                case CompositeImagesTool.name:
                    return try ToolHandlers.composite(arguments: params.arguments)
                case AppStoreScreenshotsTool.name:
                    return try ToolHandlers.appStore(arguments: params.arguments)
                case ListFramesTool.name:
                    return ToolHandlers.listFrames()
                case RemoveBackgroundTool.name:
                    return try ToolHandlers.removeBackground(arguments: params.arguments)
                case SmartCropTool.name:
                    return try ToolHandlers.smartCrop(arguments: params.arguments)
                default:
                    return CallTool.Result(
                        content: [.text(
                            text: "Unknown tool: \(params.name)",
                            annotations: nil,
                            _meta: nil
                        )],
                        isError: true
                    )
                }
            } catch let error as MCPError {
                // Schema-level argument problems: bubble up so the SDK can
                // return a proper JSON-RPC error code.
                throw error
            } catch let error as SwiftMageXError {
                // Defensive — handlers normally catch this themselves and turn
                // it into `isError: true`. Reach here only if a kit error
                // escapes the handler boundary.
                return CallTool.Result(
                    content: [.text(
                        text: "[\(error.category)] \(error.message)",
                        annotations: nil,
                        _meta: nil
                    )],
                    isError: true
                )
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    /// Constructs the right production provider for the model named in
    /// `arguments`, surfacing a missing API key as
    /// ``SwiftMageXError/configuration(_:)`` — the same mapping the CLI uses,
    /// so the calling agent sees a consistent error category (spec §13).
    /// Falls back to the default model when `arguments` omits `model` so the
    /// catalog-default Gemini provider is always available.
    private static func makeImageProvider(
        for arguments: [String: Value]?
    ) throws -> any ImageProvider {
        guard let apiKey = Configuration.resolvedAPIKey() else {
            throw SwiftMageXError.configuration(
                "missing \(Configuration.EnvironmentKey.primaryAPIKey)"
            )
        }
        let requestedModel = (arguments?["model"]).flatMap { value -> String? in
            if case let .string(string) = value { return string }
            return nil
        } ?? ModelCatalog.defaultModelID
        return SwiftMageXOrchestrator.makeProvider(for: requestedModel, apiKey: apiKey)
    }
}

/// Convenience registry of the tools this server exposes.
enum SwiftMageXTools {
    static let all: [Tool] = [
        GenerateImageTool.descriptor,
        ResizeImageTool.descriptor,
        OverlayTextTool.descriptor,
        CompositeImagesTool.descriptor,
        AppStoreScreenshotsTool.descriptor,
        ListFramesTool.descriptor,
        RemoveBackgroundTool.descriptor,
        SmartCropTool.descriptor,
    ]
}
