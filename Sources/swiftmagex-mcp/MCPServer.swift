import Foundation
import MCP
import SwiftMageXKit

/// Entry point for `swiftmagex-mcp` — an MCP server over stdio.
///
/// Spec §7. Boots an MCP `Server`, registers the three tools that mirror the
/// CLI commands, and waits for the client to close stdin. Tool handlers route
/// by name and currently return `isError: true` until milestone 7 wires them
/// to ``SwiftMageXKit``.
@main
struct MCPServerMain {
    static func main() async throws {
        let server = Server(
            name: "swiftmagex-mcp",
            version: "0.1.0",
            instructions: """
            SwiftMageX MCP server. Provides three tools mirroring the CLI:
            generate_image, resize_image, overlay_text. Tool results return
            absolute file paths because the calling agent does not know the
            server's working directory.
            """,
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: SwiftMageXTools.all)
        }

        await server.withMethodHandler(CallTool.self) { params in
            // TODO(milestone 7): dispatch to SwiftMageXKit. Inputs are validated
            // by the per-tool input schemas declared in SwiftMageXTools.
            switch params.name {
            case GenerateImageTool.name:
                return notImplemented(GenerateImageTool.name)
            case ResizeImageTool.name:
                return notImplemented(ResizeImageTool.name)
            case OverlayTextTool.name:
                return notImplemented(OverlayTextTool.name)
            default:
                return CallTool.Result(
                    content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    private static func notImplemented(_ toolName: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(
                text: "\(toolName) is not implemented yet (milestone 7).",
                annotations: nil,
                _meta: nil
            )],
            isError: true
        )
    }
}

/// Convenience registry of the three tools this server exposes.
enum SwiftMageXTools {
    static let all: [Tool] = [
        GenerateImageTool.descriptor,
        ResizeImageTool.descriptor,
        OverlayTextTool.descriptor,
    ]
}
