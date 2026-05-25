import ArgumentParser
import Foundation
import SwiftMageXKit

/// `swiftmagex appstore <screenshot> --background <bg> [options]` — App Store
/// Connect screenshot preparation.
///
/// Frames a screenshot inside a user-supplied iPhone bezel, scales it onto a
/// background, optionally overlays a caption, and writes the result at one or
/// more ASC iPhone pixel sizes. Local raster work — no AI, no API key.
struct AppStoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appstore",
        abstract: "Prepare App Store Connect screenshots — frame, caption, batch-resize.",
        helpNames: [.long]
    )

    @Argument(help: "Screenshot image to place into the device frame.")
    var screenshot: String

    @Option(name: .long, help: "Background image filled behind the device.")
    var background: String

    @Option(name: .long, help: "Device bezel PNG with a transparent screen cutout. Omit to skip framing.")
    var frame: String?

    @Option(
        name: .customLong("screen-rect"),
        help: ArgumentHelp(
            "Screen cutout inside the frame as x,y,width,height (pixels). Omit to auto-detect from the frame's alpha.",
            valueName: "x,y,w,h"
        )
    )
    var screenRect: String?

    @Option(
        name: .long,
        parsing: .singleValue,
        help: ArgumentHelp(
            "ASC device size to produce (repeatable). Use 'all' for every size.",
            valueName: ASCDeviceCatalog.all.map(\.id).joined(separator: "|") + "|all"
        )
    )
    var device: [String] = []

    @Option(
        name: .long,
        help: ArgumentHelp("Canvas orientation.", valueName: "portrait|landscape")
    )
    var orientation: Orientation = .portrait

    // MARK: Placement of the framed device on the background

    @Option(name: .long, help: "Framed-device size as a fraction of the canvas (0–1+).")
    var scale: Double = 0.85

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Anchor of the framed device on the canvas.",
            valueName: "top|center|bottom|top-left|top-right|bottom-left|bottom-right"
        )
    )
    var position: TextPosition = .center

    @Option(name: .customLong("offset-x"), help: "Horizontal nudge in pixels (positive = right).")
    var offsetX: Int = 0

    @Option(name: .customLong("offset-y"), help: "Vertical nudge in pixels (positive = down).")
    var offsetY: Int = 0

    // MARK: Optional caption

    @Option(name: .long, help: "Caption text overlaid on the canvas. Omit for no caption.")
    var caption: String?

    @Option(
        name: .customLong("caption-position"),
        help: ArgumentHelp(
            "Anchor position of the caption.",
            valueName: "top|center|bottom|top-left|top-right|bottom-left|bottom-right"
        )
    )
    var captionPosition: TextPosition = .bottom

    @Option(name: .long, help: "Caption font family name. Defaults to the system font.")
    var font: String?

    @Option(name: .customLong("font-size"), help: "Caption glyph point size.")
    var fontSize: Int = 96

    @Option(name: .long, help: "Caption fill color in #RRGGBB or #RRGGBBAA form.")
    var color: String = "#FFFFFF"

    @Option(name: .long, help: "Caption stroke color in #RRGGBB form. Omit for no stroke.")
    var stroke: String?

    @Option(name: .customLong("stroke-width"), help: "Caption stroke width in points.")
    var strokeWidth: Double = 0.0

    @Option(name: [.customShort("o"), .long], help: "Output directory. Defaults to the current directory.")
    var output: String = "./"

    @OptionGroup var globals: GlobalOptions

    func validate() throws {
        // Surface unknown device ids early with exit code 2.
        _ = try resolveDevices()
        if screenRect != nil {
            _ = try parseScreenRect()
        }
        guard scale > 0 else {
            throw ValidationError("--scale must be positive (got \(scale)).")
        }
        guard fontSize > 0 else {
            throw ValidationError("--font-size must be positive (got \(fontSize)).")
        }
        guard strokeWidth >= 0 else {
            throw ValidationError("--stroke-width must be non-negative (got \(strokeWidth)).")
        }
        if let caption = caption,
           caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError("--caption must not be empty when provided.")
        }
    }

    func run() async throws {
        let printer = ResultPrinter(json: globals.json, verbose: globals.verbose)

        do {
            let devices = try resolveDevices()
            let frameSpec = DeviceFrameSpec(screenRect: try parseScreenRect())
            let placement = CompositeSpec(
                position: position,
                scale: scale,
                offsetX: offsetX,
                offsetY: offsetY,
                opacity: 1.0
            )
            let captionSpec = caption.map { text in
                TextSpec(
                    text: text,
                    position: captionPosition,
                    fontName: font,
                    fontSize: fontSize,
                    color: color,
                    strokeColor: stroke,
                    strokeWidth: strokeWidth
                )
            }

            let written = try SwiftMageXOrchestrator.prepareAppStoreScreenshots(
                screenshot: screenshot,
                background: background,
                frame: frame,
                frameSpec: frameSpec,
                caption: captionSpec,
                devices: devices,
                placement: placement,
                orientation: orientation,
                output: output.isEmpty ? nil : output
            )
            let outputs = written.map { image in
                JSONResultEnvelope.Output(
                    path: image.path.path,
                    format: image.format,
                    width: image.width,
                    height: image.height
                )
            }
            printer.printSuccess(command: "appstore", outputs: outputs)
        } catch let error as SwiftMageXError {
            printer.printError(error, command: "appstore")
            throw ExitCode(error.exitCode)
        }
    }

    // MARK: - Parsing helpers

    private func resolveDevices() throws -> [ASCDeviceSize] {
        do {
            return try ASCDeviceCatalog.sizes(for: device)
        } catch let error as SwiftMageXError {
            throw ValidationError(error.message)
        }
    }

    /// Parses `--screen-rect x,y,w,h` into a ``DeviceFrameSpec/ScreenRect``;
    /// returns `nil` when the flag is absent (auto-detect).
    private func parseScreenRect() throws -> DeviceFrameSpec.ScreenRect? {
        guard let raw = screenRect else { return nil }
        let parts = raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 4, let nums = try? parts.map({ part -> Int in
            guard let n = Int(part) else { throw ValidationError("") }
            return n
        }) else {
            throw ValidationError("--screen-rect must be four integers: x,y,width,height (got '\(raw)').")
        }
        guard nums[2] > 0, nums[3] > 0 else {
            throw ValidationError("--screen-rect width and height must be positive (got '\(raw)').")
        }
        return DeviceFrameSpec.ScreenRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
    }
}

extension Orientation: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    public static var allValueStrings: [String] { Self.allCases.map(\.rawValue) }
}
