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

    // MARK: - Registry

    func testToolRegistryExposesAllThreeNames() {
        let names = Set(SwiftMageXTools.all.map(\.name))
        XCTAssertEqual(names, [
            GenerateImageTool.name,
            ResizeImageTool.name,
            OverlayTextTool.name,
        ])
    }

    // MARK: - Helpers

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
