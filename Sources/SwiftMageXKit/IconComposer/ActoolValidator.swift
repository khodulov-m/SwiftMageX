import Foundation

/// Result of compiling a `.icon` package for validation.
public struct IconValidationReport: Sendable, Equatable {
    /// True when the package compiled without errors.
    public let passed: Bool
    /// Trimmed combined stdout + stderr of the compiler, for diagnostics.
    public let output: String

    public init(passed: Bool, output: String) {
        self.passed = passed
        self.output = output
    }
}

/// Compile-checks a `.icon` package. Protocol-shaped so tests can stub the
/// result without Xcode installed.
public protocol IconValidating: Sendable {
    func validate(packageAt url: URL) throws -> IconValidationReport
}

/// Validates by compiling the package with Xcode's `actool` into a throwaway
/// directory — the same step Xcode runs at build time, so a pass here means
/// the package is consumable by a real project.
///
/// `actool` is a system binary reached through `xcrun`; invoking it with
/// Foundation `Process` keeps the kit free of package dependencies.
public struct ActoolIconValidator: IconValidating {
    public init() {}

    public func validate(packageAt url: URL) throws -> IconValidationReport {
        let actool = try locateActool()

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-actool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let result = try run(executable: actool, arguments: [
            url.path,
            "--compile", scratch.path,
            "--platform", "iphoneos",
            "--minimum-deployment-target", "26.0",
            "--app-icon", url.deletingPathExtension().lastPathComponent,
            "--output-format", "human-readable-text",
            "--output-partial-info-plist",
            scratch.appendingPathComponent("partial.plist").path,
        ])

        // actool exits 0 even for broken packages (a missing layer image is
        // reported as "warning: Icon export exited with status 255"), so the
        // status and output text alone are unreliable. The strongest signal
        // is the artifact itself: a successful compile always produces
        // Assets.car in the output directory.
        let producedCar = FileManager.default.fileExists(
            atPath: scratch.appendingPathComponent("Assets.car").path
        )
        let failed = !producedCar
            || result.status != 0
            || result.output.contains("com.apple.actool.errors")
            || result.output.contains(": error:")
        return IconValidationReport(passed: !failed, output: result.output)
    }

    private func locateActool() throws -> URL {
        let result: (status: Int32, output: String)
        do {
            result = try run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["--find", "actool"]
            )
        } catch {
            throw SwiftMageXError.configuration(
                "xcrun is unavailable; install Xcode 26 to use icon validation"
            )
        }
        guard result.status == 0, !result.output.isEmpty else {
            throw SwiftMageXError.configuration(
                "actool not found; icon validation requires Xcode 26 with Icon Composer support"
            )
        }
        return URL(fileURLWithPath: result.output)
    }

    private func run(
        executable: URL,
        arguments: [String]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw SwiftMageXError.configuration(
                "could not launch \(executable.path): \(error.localizedDescription)"
            )
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (
            process.terminationStatus,
            output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
