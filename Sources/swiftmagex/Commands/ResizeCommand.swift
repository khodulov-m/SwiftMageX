import ArgumentParser
import Foundation
import SwiftMageXKit

/// `swiftmagex resize <input> [options]` — local resize / crop / format conversion.
///
/// Per spec §6.2. No AI, no API key required. Stubbed until milestone 2.
struct ResizeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resize",
        abstract: "Resize, crop, or convert an image locally — no AI.",
        // Spec §6.2 reserves `-h` for `--height`. Drop the short help alias
        // here so the two flags don't collide.
        helpNames: [.long]
    )

    @Argument(help: "Source image file.")
    var input: String

    @Option(name: [.customShort("w"), .long], help: "Target width in pixels.")
    var width: Int?

    // Spec §6.2 reserves `-h` for `--height`; ArgumentParser's default
    // help short is `-h` too, so we drop the short alias for help here.
    @Option(name: [.customShort("h"), .long], help: "Target height in pixels.")
    var height: Int?

    @Option(
        name: .long,
        help: ArgumentHelp("Fit mode applied to the target size.", valueName: "contain|cover|fill")
    )
    var fit: ResizeFit = .contain

    @Option(name: [.customShort("o"), .long], help: "Destination file. Defaults to a sibling of the source.")
    var output: String?

    @Option(
        name: .long,
        help: ArgumentHelp("Output format. Defaults to the source format.", valueName: "png|jpeg")
    )
    var format: ImageFormat?

    @Option(name: .long, help: "JPEG quality, 0.0–1.0.")
    var quality: Double = 0.9

    @OptionGroup var globals: GlobalOptions

    func validate() throws {
        if width == nil && height == nil {
            throw ValidationError("Provide at least one of --width or --height.")
        }
        if let w = width, w <= 0 {
            throw ValidationError("--width must be positive (got \(w)).")
        }
        if let h = height, h <= 0 {
            throw ValidationError("--height must be positive (got \(h)).")
        }
        guard (0.0...1.0).contains(quality) else {
            throw ValidationError("--quality must be between 0.0 and 1.0 (got \(quality)).")
        }
    }

    func run() async throws {
        // TODO(milestone 2): load via CoreImageRasterEngine, build a ResizeSpec,
        // resize, write to the resolved output path, and emit a result via
        // ResultPrinter (human or JSON).
        FileHandle.standardError.write(Data(
            "swiftmagex resize is not implemented yet (milestone 2).\n".utf8
        ))
        throw ExitCode(1)
    }
}

extension ResizeFit: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    public static var allValueStrings: [String] { Self.allCases.map(\.rawValue) }
}

extension ImageFormat: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument.lowercased() {
        case "png": self = .png
        case "jpeg", "jpg": self = .jpeg
        default: return nil
        }
    }

    public static var allValueStrings: [String] { ["png", "jpeg"] }
}
