import MCP
import SwiftMageXKit

/// `list_frames` — exposes the kit's bundled device-frame catalog so callers
/// can discover what `frame` values `appstore_screenshots` accepts without
/// shelling out to the CLI's `--list-frames`.
enum ListFramesTool {
    /// MCP tool name.
    static let name = "list_frames"

    /// MCP tool descriptor. No inputs.
    static let descriptor = Tool(
        name: name,
        description: "List the device bezels bundled with SwiftMageX. Returns frame ids that `appstore_screenshots`'s `frame` argument accepts, plus their target ASC device id and licence metadata.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )
}
