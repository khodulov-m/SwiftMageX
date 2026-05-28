import Foundation
import MCP
import SwiftMageXKit
import XCTest
@testable import swiftmagex_mcp

final class ToolHandlersTests: XCTestCase {
    // MARK: - generate_image

    func testGenerateImageToolReturnsAbsolutePathsAndImageContent() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pngBytes = try TestPNG.bytes(width: 16, height: 16)
        let provider = StubImageProvider(images: [
            GeneratedImage(data: pngBytes, format: .png, prompt: "p", model: "m", seed: nil),
            GeneratedImage(data: pngBytes, format: .png, prompt: "p", model: "m", seed: nil),
        ])

        let arguments: [String: Value] = [
            "prompt": .string("test prompt"),
            "count": .int(2),
            "output": .string(dir.path),
        ]

        let result = try await ToolHandlers.generate(
            arguments: arguments,
            provider: provider
        )

        XCTAssertNotEqual(result.isError, true)
        let text = try XCTUnwrap(result.firstText)
        XCTAssertTrue(text.hasPrefix("OK\n"), "summary should begin with OK, got:\n\(text)")

        // Extract paths from the summary lines and verify they are absolute.
        let pathLines = text.split(separator: "\n").filter { $0.contains(".png") }
        XCTAssertEqual(pathLines.count, 2, "expected 2 generated paths in summary")
        for line in pathLines {
            let path = String(line.split(separator: " ").first ?? "")
            XCTAssertTrue(
                path.hasPrefix("/"),
                "MCP results must report absolute paths (spec §7): got \(path)"
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "expected file at \(path)")
        }

        // Spec §7: generated images echoed back inline so the calling model
        // can inspect them.
        let images = result.imageContents
        XCTAssertEqual(images.count, 2, "expected 2 image content blocks alongside text")
        for image in images {
            XCTAssertEqual(image.mimeType, "image/png")
            XCTAssertFalse(image.data.isEmpty)
        }
    }

    func testGenerateImageToolMissingPromptReturnsInvalidParams() async {
        let provider = StubImageProvider(images: [])
        do {
            _ = try await ToolHandlers.generate(arguments: [:], provider: provider)
            XCTFail("expected MCPError.invalidParams")
        } catch let error as MCPError {
            guard case .invalidParams = error else {
                return XCTFail("expected .invalidParams, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testGenerateImageToolMapsProviderErrorToIsError() async throws {
        let provider = StubImageProvider(throwing: .provider("simulated upstream failure"))
        let arguments: [String: Value] = ["prompt": .string("anything")]

        let result = try await ToolHandlers.generate(
            arguments: arguments,
            provider: provider
        )
        XCTAssertEqual(result.isError, true)
        let text = try XCTUnwrap(result.firstText)
        XCTAssertTrue(text.contains("[provider]"), "expected category tag in error text, got: \(text)")
    }

    // MARK: - resize_image

    func testResizeImageToolWritesAbsolutePath() throws {
        let fixture = try TestPNG.writeFixture(width: 20, height: 20)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }

        let arguments: [String: Value] = [
            "input": .string(fixture.path),
            "width": .int(10),
            "height": .int(10),
            "fit": .string("fill"),
        ]
        let result = try ToolHandlers.resize(arguments: arguments)
        XCTAssertNotEqual(result.isError, true)
        let text = try XCTUnwrap(result.firstText)
        let line = try XCTUnwrap(text.split(separator: "\n").last)
        let path = String(line.split(separator: " ").first ?? "")
        XCTAssertTrue(path.hasPrefix("/"), "absolute path required, got \(path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testResizeImageToolMissingInputReturnsInvalidParams() {
        do {
            _ = try ToolHandlers.resize(arguments: [
                "width": .int(100),
                "height": .int(100),
            ])
            XCTFail("expected MCPError.invalidParams for missing 'input'")
        } catch let error as MCPError {
            guard case .invalidParams(let detail) = error else {
                return XCTFail("expected .invalidParams, got \(error)")
            }
            XCTAssertTrue((detail ?? "").contains("input"), "error should mention 'input': \(detail ?? "")")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testResizeImageToolMissingFileMapsToIOError() throws {
        let arguments: [String: Value] = [
            "input": .string("/tmp/does-not-exist-\(UUID().uuidString).png"),
            "width": .int(10),
        ]
        let result = try ToolHandlers.resize(arguments: arguments)
        XCTAssertEqual(result.isError, true)
        let text = try XCTUnwrap(result.firstText)
        XCTAssertTrue(text.contains("[io]"), "expected io category in error text: \(text)")
    }

    func testResizeImageToolCoverWithoutBothDimensionsRejected() {
        do {
            _ = try ToolHandlers.resize(arguments: [
                "input": .string("/anything.png"),
                "width": .int(100),
                "fit": .string("cover"),
            ])
            XCTFail("expected MCPError.invalidParams for cover without both dims")
        } catch let error as MCPError {
            guard case .invalidParams = error else {
                return XCTFail("expected .invalidParams, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - overlay_text

    func testOverlayTextToolWritesAbsolutePath() throws {
        let fixture = try TestPNG.writeFixture(width: 40, height: 40)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }

        let arguments: [String: Value] = [
            "input": .string(fixture.path),
            "text": .string("HI"),
            "position": .string("bottom"),
        ]
        let result = try ToolHandlers.overlayText(arguments: arguments)
        XCTAssertNotEqual(result.isError, true)
        let text = try XCTUnwrap(result.firstText)
        let line = try XCTUnwrap(text.split(separator: "\n").last)
        let path = String(line.split(separator: " ").first ?? "")
        XCTAssertTrue(path.hasPrefix("/"), "absolute path required, got \(path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testOverlayTextToolMissingTextReturnsInvalidParams() {
        do {
            _ = try ToolHandlers.overlayText(arguments: [
                "input": .string("/anything.png"),
            ])
            XCTFail("expected MCPError.invalidParams for missing 'text'")
        } catch let error as MCPError {
            guard case .invalidParams = error else {
                return XCTFail("expected .invalidParams, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testOverlayTextToolInvalidColorMapsToInvalidInput() throws {
        let fixture = try TestPNG.writeFixture(width: 30, height: 30)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }

        let result = try ToolHandlers.overlayText(arguments: [
            "input": .string(fixture.path),
            "text": .string("HI"),
            "color": .string("#ZZZ"),
        ])
        XCTAssertEqual(result.isError, true)
        let text = try XCTUnwrap(result.firstText)
        XCTAssertTrue(text.contains("[invalid_input]"), "expected invalid_input category: \(text)")
    }

    // MARK: - composite_images

    func testCompositeImagesToolWritesAbsolutePath() throws {
        let bg = try TestPNG.writeFixture(width: 80, height: 80)
        let fg = try TestPNG.writeFixture(width: 20, height: 20)
        defer {
            try? FileManager.default.removeItem(at: bg.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: fg.deletingLastPathComponent())
        }

        let arguments: [String: Value] = [
            "input": .string(bg.path),
            "overlay": .string(fg.path),
            "scale": .double(0.5),
            "position": .string("center"),
        ]
        let result = try ToolHandlers.composite(arguments: arguments)
        XCTAssertNotEqual(result.isError, true)
        let text = try XCTUnwrap(result.firstText)
        let line = try XCTUnwrap(text.split(separator: "\n").last)
        let path = String(line.split(separator: " ").first ?? "")
        XCTAssertTrue(path.hasPrefix("/"), "absolute path required, got \(path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testCompositeImagesToolMissingOverlayReturnsInvalidParams() {
        do {
            _ = try ToolHandlers.composite(arguments: ["input": .string("/anything.png")])
            XCTFail("expected MCPError.invalidParams for missing 'overlay'")
        } catch let error as MCPError {
            guard case .invalidParams = error else {
                return XCTFail("expected .invalidParams, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - appstore_screenshots

    func testAppStoreScreenshotsToolBatchesToDeviceSizes() throws {
        let shot = try TestPNG.writeFixture(width: 60, height: 130)
        let bg = try TestPNG.writeFixture(width: 200, height: 400)
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-appstore-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: shot.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: bg.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: outDir)
        }

        let arguments: [String: Value] = [
            "screenshot": .string(shot.path),
            "background": .string(bg.path),
            "devices": .array([.string("iphone-5.5")]),
            "caption": .string("Hello"),
            "output": .string(outDir.path),
        ]
        let result = try ToolHandlers.appStore(arguments: arguments)
        XCTAssertNotEqual(result.isError, true)
        let text = try XCTUnwrap(result.firstText)
        let pathLines = text.split(separator: "\n").filter { $0.contains(".png") }
        XCTAssertEqual(pathLines.count, 1)
        let line = try XCTUnwrap(pathLines.first)
        let path = String(line.split(separator: " ").first ?? "")
        XCTAssertTrue(path.hasPrefix("/"), "absolute path required, got \(path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(text.contains("1242x2208"), "summary should report ASC pixel size: \(text)")
    }

    func testAppStoreScreenshotsToolMissingBackgroundReturnsInvalidParams() {
        do {
            _ = try ToolHandlers.appStore(arguments: ["screenshot": .string("/anything.png")])
            XCTFail("expected MCPError.invalidParams for missing 'background'")
        } catch let error as MCPError {
            guard case .invalidParams = error else {
                return XCTFail("expected .invalidParams, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testAppStoreScreenshotsToolUnknownDeviceReturnsInvalidParams() {
        do {
            _ = try ToolHandlers.appStore(arguments: [
                "screenshot": .string("/a.png"),
                "background": .string("/b.png"),
                "devices": .array([.string("iphone-99")]),
            ])
            XCTFail("expected MCPError.invalidParams for unknown device")
        } catch let error as MCPError {
            guard case .invalidParams = error else {
                return XCTFail("expected .invalidParams, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - remove_background

    func testRemoveBackgroundToolMissingInputReturnsInvalidParams() {
        do {
            _ = try ToolHandlers.removeBackground(arguments: [:])
            XCTFail("expected MCPError.invalidParams for missing 'input'")
        } catch let error as MCPError {
            guard case .invalidParams(let detail) = error else {
                return XCTFail("expected .invalidParams, got \(error)")
            }
            XCTAssertTrue((detail ?? "").contains("input"), "error should mention 'input': \(detail ?? "")")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testRemoveBackgroundToolMissingFileMapsToIOError() throws {
        let arguments: [String: Value] = [
            "input": .string("/tmp/does-not-exist-\(UUID().uuidString).png"),
        ]
        let result = try ToolHandlers.removeBackground(arguments: arguments)
        XCTAssertEqual(result.isError, true)
        let text = try XCTUnwrap(result.firstText)
        XCTAssertTrue(text.contains("[io]"), "expected io category in error text: \(text)")
    }

    // MARK: - Registry

    func testToolRegistryExposesAllToolNames() {
        let names = Set(SwiftMageXTools.all.map(\.name))
        XCTAssertEqual(names, [
            GenerateImageTool.name,
            ResizeImageTool.name,
            OverlayTextTool.name,
            CompositeImagesTool.name,
            AppStoreScreenshotsTool.name,
            ListFramesTool.name,
            RemoveBackgroundTool.name,
            SmartCropTool.name,
        ])
    }

    func testListFramesReportsBundledCatalog() {
        let result = ToolHandlers.listFrames()
        XCTAssertEqual(result.isError, false)
        let text = (try? XCTUnwrap(result.firstText)) ?? ""
        XCTAssertTrue(text.hasPrefix("OK"))
        XCTAssertTrue(
            text.contains("iphone-6.5-pommeplate-spacegray"),
            "list_frames must surface the bundled CC0 PommePlate bezel: \(text)"
        )
    }

    // MARK: - Helpers

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
