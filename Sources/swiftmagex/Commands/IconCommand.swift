import ArgumentParser
import Foundation
import SwiftMageXKit

/// `swiftmagex icon <layer>... [options]` — assemble an Icon Composer
/// `.icon` package (Liquid Glass app icons, iOS 26+/macOS 26+).
///
/// Local-only: stacks prepared layer images on the 1024-pt canvas, writes
/// `icon.json` plus `Assets/`, and reports the absolute package path. Layer
/// preparation (cutouts, resizing) belongs to `remove-bg` / `resize`.
struct IconCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "icon",
        abstract: "Assemble an Icon Composer .icon package from layer images — no AI, no key."
    )

    @Argument(help: ArgumentHelp(
        "Layer images bottom-to-top. Append comma-separated options to a path: "
            + "name=…, glass=true|false, scale=N, dx=N, dy=N, fill=#RRGGBB[AA], group=N.",
        valueName: "path[,key=value...]"
    ))
    var layers: [String]

    @Option(name: [.customShort("o"), .long], help: ArgumentHelp(
        "Destination .icon path ('.icon' appended when missing). Defaults to AppIcon.icon in the current directory.",
        valueName: "path"
    ))
    var output: String?

    @Option(name: .long, help: ArgumentHelp(
        "Icon background: solid color or system gradient seeded from one color.",
        valueName: "solid:#HEX|auto:#HEX"
    ))
    var fill: String = "solid:#FFFFFF"

    @Flag(name: .long, help: "Replace an existing package atomically.")
    var overwrite = false

    @Flag(name: .long, help: "Also write a flat 1024x1024 PNG composite next to the package.")
    var flatPreview = false

    @Option(name: .long, help: ArgumentHelp(
        "Path for the flat preview PNG. Defaults to '<name>-flat.png' beside the package.",
        valueName: "path"
    ))
    var flatPreviewOutput: String?

    // Property name differs from the flag because `validate` would collide
    // with ParsableCommand's validate() requirement.
    @Flag(
        name: .customLong("validate"),
        help: "Compile-check the package with Xcode's actool (requires Xcode 26)."
    )
    var runValidation = false

    @OptionGroup var globals: GlobalOptions

    func validate() throws {
        guard !layers.isEmpty else {
            throw ValidationError("Provide at least one layer image.")
        }
        _ = try layers.map(Self.parseLayer)
        do {
            _ = try IconFill.parse(fill)
        } catch let error as SwiftMageXError {
            throw ValidationError("--fill: \(error.message)")
        }
    }

    func run() async throws {
        let printer = ResultPrinter(json: globals.json, verbose: globals.verbose)

        do {
            let package = try SwiftMageXOrchestrator.composeIcon(
                layers: try layers.map(Self.parseLayer),
                fill: try IconFill.parse(fill),
                output: output,
                overwrite: overwrite,
                flatPreview: flatPreview,
                flatPreviewOutput: flatPreviewOutput,
                validate: runValidation
            )
            if package.validation != nil {
                printer.diagnostic("actool validation passed")
            }
            var outputs = [JSONResultEnvelope.Output(
                path: package.packagePath.path,
                formatName: "icon"
            )]
            if let preview = package.flatPreview {
                outputs.append(JSONResultEnvelope.Output(
                    path: preview.path.path,
                    format: preview.format,
                    width: preview.width,
                    height: preview.height
                ))
            }
            printer.printSuccess(command: "icon", outputs: outputs)
        } catch let error as SwiftMageXError {
            printer.printError(error, command: "icon")
            throw ExitCode(error.exitCode)
        } catch let error as ValidationError {
            // parseLayer / IconFill.parse re-run inside run(); validate()
            // already vetted them, so this is unreachable in practice.
            printer.printError(.invalidInput(error.message), command: "icon")
            throw ExitCode(2)
        }
    }

    /// Parses one `path[,key=value,...]` layer argument. Comma segments
    /// without `=` belong to the path (file names may contain commas);
    /// everything after the first `key=value` segment must be an option.
    /// Throws `ValidationError` so ArgumentParser reports usage problems
    /// before `run()` (exit code 2 via the entry-point remap).
    static func parseLayer(_ raw: String) throws -> IconLayerSpec {
        let segments = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard let first = segments.first, !first.isEmpty else {
            throw ValidationError("Layer argument must start with an image path (got \"\(raw)\").")
        }

        let optionStart = segments.firstIndex { $0.contains("=") } ?? segments.endIndex
        let path = segments[..<optionStart].joined(separator: ",")
        guard !path.isEmpty else {
            throw ValidationError("Layer argument must start with an image path (got \"\(raw)\").")
        }

        var spec = IconLayerSpec(path: path)
        for segment in segments[optionStart...] {
            let pair = segment.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, !pair[1].isEmpty else {
                throw ValidationError("Malformed layer option \"\(segment)\"; use key=value.")
            }
            let key = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(pair[1])
            switch key {
            case "name":
                spec.name = value
            case "glass":
                guard let parsed = Bool(value.lowercased()) else {
                    throw ValidationError("glass must be true or false (got \"\(value)\").")
                }
                spec.glass = parsed
            case "scale":
                spec.scale = try positiveDouble(value, key: "scale")
            case "dx":
                spec.dx = try double(value, key: "dx")
            case "dy":
                spec.dy = try double(value, key: "dy")
            case "fill":
                do {
                    _ = try IconFill.parse("solid:\(value)")
                } catch let error as SwiftMageXError {
                    throw ValidationError("fill: \(error.message)")
                }
                spec.fill = value
            case "group":
                guard let parsed = Int(value), parsed >= 1 else {
                    throw ValidationError("group must be a positive integer (got \"\(value)\").")
                }
                spec.group = parsed
            default:
                throw ValidationError(
                    "Unknown layer option \"\(key)\"; expected name, glass, scale, dx, dy, fill, or group."
                )
            }
        }
        return spec
    }

    private static func double(_ value: String, key: String) throws -> Double {
        guard let parsed = Double(value) else {
            throw ValidationError("\(key) must be a number (got \"\(value)\").")
        }
        return parsed
    }

    private static func positiveDouble(_ value: String, key: String) throws -> Double {
        let parsed = try double(value, key: key)
        guard parsed > 0 else {
            throw ValidationError("\(key) must be positive (got \"\(value)\").")
        }
        return parsed
    }
}
