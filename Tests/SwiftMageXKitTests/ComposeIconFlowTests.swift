import CoreGraphics
import XCTest
@testable import SwiftMageXKit

/// End-to-end `composeIcon` orchestration: package layout, asset copying,
/// overwrite semantics, the flat preview, and validator wiring.
final class ComposeIconFlowTests: XCTestCase {
    func testComposeWritesPackageStructure() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let back = try writeColorPNG(dir, "back.png", width: 32, height: 32, r: 10, g: 20, b: 30)
        let front = try writeColorPNG(dir, "front.png", width: 16, height: 16, r: 200, g: 0, b: 0)

        let package = try SwiftMageXOrchestrator.composeIcon(
            layers: [
                IconLayerSpec(path: back.path),
                IconLayerSpec(path: front.path, glass: false, scale: 2, dx: 100, group: 2),
            ],
            fill: .automaticGradient("#7B1FA2"),
            output: dir.appendingPathComponent("MyIcon").path
        )

        XCTAssertTrue(package.packagePath.path.hasPrefix("/"), "package path must be absolute")
        XCTAssertEqual(package.packagePath.lastPathComponent, "MyIcon.icon")
        XCTAssertEqual(package.layerCount, 2)
        XCTAssertEqual(package.groupCount, 2)
        XCTAssertNil(package.flatPreview)
        XCTAssertNil(package.validation)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: package.packagePath.path, isDirectory: &isDirectory
        ))
        XCTAssertTrue(isDirectory.boolValue, ".icon must be a directory package")

        let assets = try FileManager.default.contentsOfDirectory(
            atPath: package.packagePath.appendingPathComponent("Assets").path
        )
        XCTAssertEqual(assets.sorted(), ["back.png", "front.png"])

        let document = try JSONDecoder().decode(
            IconComposerDocument.self,
            from: Data(contentsOf: package.packagePath.appendingPathComponent("icon.json"))
        )
        XCTAssertEqual(document.groups.count, 2)
        // Front-most group first; per-layer options must round-trip.
        XCTAssertEqual(document.groups[0].layers.map(\.name), ["front"])
        XCTAssertEqual(document.groups[0].layers[0].glass, false)
        XCTAssertEqual(document.groups[0].layers[0].position?.scale, 2)
        XCTAssertEqual(document.groups[0].layers[0].position?.translationInPoints, [100, 0])
        XCTAssertEqual(document.groups[1].layers.map(\.name), ["back"])
        XCTAssertEqual(document.fill, .automaticGradient("srgb:0.48235,0.12157,0.63529,1.00000"))
    }

    func testPNGLayersAreCopiedVerbatim() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeColorPNG(dir, "art.png", width: 12, height: 12, r: 1, g: 2, b: 3)

        let package = try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: source.path)],
            output: dir.appendingPathComponent("Verbatim").path
        )

        let copied = package.packagePath.appendingPathComponent("Assets/art.png")
        XCTAssertEqual(
            try Data(contentsOf: copied),
            try Data(contentsOf: source),
            "PNG sources must be copied byte-for-byte, not re-encoded"
        )
    }

    func testNonPNGLayerIsReencodedToPNG() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = CoreImageRasterEngine()
        let jpeg = dir.appendingPathComponent("photo.jpeg")
        let image = try engine.load(
            from: try writeColorPNG(dir, "seed.png", width: 10, height: 10, r: 9, g: 9, b: 9)
        )
        try engine.write(image, to: jpeg, format: .jpeg, quality: 0.9, metadata: nil)

        let package = try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: jpeg.path)],
            output: dir.appendingPathComponent("Reencoded").path
        )

        let asset = package.packagePath.appendingPathComponent("Assets/photo.png")
        XCTAssertEqual(ImageFormat.detect(at: asset), .png)
    }

    func testMissingLayerFileThrowsIO() {
        XCTAssertThrowsError(try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: "/nonexistent/layer.png")],
            output: nil
        )) { error in
            guard let smx = error as? SwiftMageXError, case .io = smx else {
                return XCTFail("Expected SwiftMageXError.io, got \(error)")
            }
        }
    }

    func testExistingOutputRequiresOverwrite() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let layer = try writeColorPNG(dir, "l.png", width: 8, height: 8, r: 5, g: 5, b: 5)
        let target = dir.appendingPathComponent("Existing").path

        _ = try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: layer.path)],
            output: target
        )

        XCTAssertThrowsError(try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: layer.path)],
            output: target
        )) { error in
            guard let smx = error as? SwiftMageXError, case .invalidInput = smx else {
                return XCTFail("Expected invalidInput without overwrite, got \(error)")
            }
        }

        // With overwrite the package is replaced wholesale: the second
        // compose has different content and the first one's assets are gone.
        let second = try writeColorPNG(dir, "l2.png", width: 8, height: 8, r: 6, g: 6, b: 6)
        let package = try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: second.path)],
            output: target,
            overwrite: true
        )
        let assets = try FileManager.default.contentsOfDirectory(
            atPath: package.packagePath.appendingPathComponent("Assets").path
        )
        XCTAssertEqual(assets, ["l2.png"])
    }

    // MARK: - Flat preview

    func testFlatPreviewCompositesLayerOverSolidFill() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let red = try writeColorPNG(dir, "red.png", width: 16, height: 16, r: 255, g: 0, b: 0)

        let package = try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: red.path)],
            fill: .solid("#0000FF"),
            output: dir.appendingPathComponent("Preview").path,
            flatPreview: true
        )

        let preview = try XCTUnwrap(package.flatPreview)
        XCTAssertEqual(preview.width, 1024)
        XCTAssertEqual(preview.height, 1024)
        XCTAssertEqual(
            preview.path.lastPathComponent,
            "Preview-flat.png",
            "default preview name derives from the package stem"
        )

        let image = try CoreImageRasterEngine().load(from: preview.path)
        // Natural size, centered: the 16-px red layer covers the canvas
        // center; corners stay the blue fill.
        assertPixel(at: (512, 512), in: image, isRoughly: (255, 0, 0))
        assertPixel(at: (4, 4), in: image, isRoughly: (0, 0, 255))
        assertPixel(at: (1020, 1020), in: image, isRoughly: (0, 0, 255))
    }

    func testFlatPreviewHonorsScaleAndCenterOffset() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let red = try writeColorPNG(dir, "red.png", width: 16, height: 16, r: 255, g: 0, b: 0)

        let package = try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: red.path, scale: 4, dx: 200, dy: 200)],
            fill: .solid("#0000FF"),
            output: dir.appendingPathComponent("Offset").path,
            flatPreview: true
        )

        let image = try CoreImageRasterEngine().load(from: try XCTUnwrap(package.flatPreview).path)
        // 16 px × 4 = 64 px block centered at (512+200, 512+200), y-down.
        assertPixel(at: (712, 712), in: image, isRoughly: (255, 0, 0))
        assertPixel(at: (512, 512), in: image, isRoughly: (0, 0, 255))
    }

    // MARK: - Validation wiring

    func testValidationReportIsReturnedOnPass() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let layer = try writeColorPNG(dir, "l.png", width: 8, height: 8, r: 5, g: 5, b: 5)

        let package = try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: layer.path)],
            output: dir.appendingPathComponent("Validated").path,
            validate: true,
            validator: StubIconValidator(result: .success(.init(passed: true, output: "ok")))
        )
        XCTAssertEqual(package.validation, IconValidationReport(passed: true, output: "ok"))
    }

    func testFailedValidationThrowsInvalidInput() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let layer = try writeColorPNG(dir, "l.png", width: 8, height: 8, r: 5, g: 5, b: 5)

        XCTAssertThrowsError(try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: layer.path)],
            output: dir.appendingPathComponent("Broken").path,
            validate: true,
            validator: StubIconValidator(result: .success(.init(passed: false, output: "boom")))
        )) { error in
            guard let smx = error as? SwiftMageXError, case .invalidInput(let message) = smx else {
                return XCTFail("Expected invalidInput, got \(error)")
            }
            XCTAssertTrue(message.contains("boom"), "actool output must reach the caller")
        }
    }

    func testMissingActoolSurfacesAsConfigurationError() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let layer = try writeColorPNG(dir, "l.png", width: 8, height: 8, r: 5, g: 5, b: 5)

        XCTAssertThrowsError(try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: layer.path)],
            output: dir.appendingPathComponent("NoXcode").path,
            validate: true,
            validator: StubIconValidator(result: .failure(.configuration("actool not found")))
        )) { error in
            guard let smx = error as? SwiftMageXError, case .configuration = smx else {
                return XCTFail("Expected configuration, got \(error)")
            }
        }
    }

    /// Real-actool integration: compiles a generated package and rejects a
    /// corrupted one. Skipped on machines without a `.icon`-capable Xcode.
    func testActoolValidatorAgainstRealActool() throws {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        probe.arguments = ["--find", "actool"]
        probe.standardOutput = Pipe()
        probe.standardError = Pipe()
        try? probe.run()
        probe.waitUntilExit()
        try XCTSkipUnless(
            probe.terminationStatus == 0,
            "actool unavailable; skipping real-validation test"
        )

        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let layer = try writeColorPNG(dir, "art.png", width: 64, height: 64, r: 40, g: 90, b: 200)

        let package = try SwiftMageXOrchestrator.composeIcon(
            layers: [IconLayerSpec(path: layer.path)],
            output: dir.appendingPathComponent("RealIcon").path
        )
        let validator = ActoolIconValidator()
        let good = try validator.validate(packageAt: package.packagePath)
        if !good.passed {
            throw XCTSkip("installed actool cannot compile .icon packages: \(good.output)")
        }

        // Corrupt the manifest: a dangling image reference must fail even
        // though actool exits 0 for it.
        let manifest = package.packagePath.appendingPathComponent("icon.json")
        let corrupted = try String(contentsOf: manifest, encoding: .utf8)
            .replacingOccurrences(of: "art.png", with: "missing.png")
        try corrupted.write(to: manifest, atomically: true, encoding: .utf8)
        let bad = try validator.validate(packageAt: package.packagePath)
        XCTAssertFalse(bad.passed, "dangling image reference must fail validation")
    }

    // MARK: - Fixtures

    private struct StubIconValidator: IconValidating {
        let result: Result<IconValidationReport, SwiftMageXError>

        func validate(packageAt url: URL) throws -> IconValidationReport {
            try result.get()
        }
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-icon-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeColorPNG(
        _ dir: URL, _ name: String, width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8
    ) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255
        }
        let cg = bytes.withUnsafeMutableBufferPointer { ptr in
            CGContext(
                data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!.makeImage()!
        }
        try CoreImageRasterEngine().write(
            RasterImage(cgImage: cg), to: url, format: .png, quality: 1.0, metadata: nil
        )
        return url
    }

    /// Samples one pixel (top-left origin) and compares RGB with tolerance —
    /// PNG round-trips through color-space conversion can shift values.
    private func assertPixel(
        at point: (x: Int, y: Int),
        in image: RasterImage,
        isRoughly expected: (r: UInt8, g: UInt8, b: UInt8),
        tolerance: Int = 4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let cg = image.cgImage
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        pixel.withUnsafeMutableBufferPointer { ptr in
            let context = CGContext(
                data: ptr.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(cg, in: CGRect(
                x: -CGFloat(point.x),
                y: CGFloat(point.y) - CGFloat(cg.height) + 1,
                width: CGFloat(cg.width),
                height: CGFloat(cg.height)
            ))
        }
        let actual = (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
        XCTAssertTrue(
            abs(actual.0 - Int(expected.r)) <= tolerance
                && abs(actual.1 - Int(expected.g)) <= tolerance
                && abs(actual.2 - Int(expected.b)) <= tolerance,
            "pixel at \(point) is \(actual), expected ~\(expected)",
            file: file,
            line: line
        )
    }
}
