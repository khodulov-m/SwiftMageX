import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SwiftMageXKit

/// Orchestrator-level tests for ``SwiftMageXOrchestrator/edit(input:mask:request:output:provider:engine:timestamp:currentDirectoryPath:)``.
///
/// Provider-level wire encoding (the inlineData parts) is covered in
/// `GeminiRequestTests`; this file verifies the surrounding pipeline: file
/// I/O, model-family gating, request augmentation, output writing, and
/// metadata embedding.
final class EditFlowTests: XCTestCase {
    // MARK: - Happy path

    func testEditWritesToAbsolutePath() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let inputURL = try Self.writePNG(in: dir, name: "src.png")
        let pngBytes = try Self.makeSolidPNGData(width: 8, height: 8)
        let request = Self.makeRequest(count: 2)
        let provider = MockImageProvider(images: [
            Self.makeImage(data: pngBytes, request: request),
            Self.makeImage(data: pngBytes, request: request)
        ])

        let written = try await SwiftMageXOrchestrator.edit(
            input: inputURL.path,
            mask: nil,
            request: request,
            output: dir.path,
            provider: provider
        )

        XCTAssertEqual(written.count, 2)
        for image in written {
            XCTAssertTrue(image.path.path.hasPrefix("/"), "Path must be absolute: \(image.path.path)")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: image.path.path),
                "File should exist at \(image.path.path)"
            )
            XCTAssertEqual(image.format, .png)
        }
    }

    func testEditEmbedsPromptInMetadata() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let inputURL = try Self.writePNG(in: dir, name: "src.png")
        let pngBytes = try Self.makeSolidPNGData(width: 8, height: 8)
        let request = Self.makeRequest(prompt: "make it green", seed: 7)
        let provider = MockImageProvider(images: [
            Self.makeImage(data: pngBytes, request: request)
        ])

        let written = try await SwiftMageXOrchestrator.edit(
            input: inputURL.path,
            mask: nil,
            request: request,
            output: dir.path,
            provider: provider
        )

        let image = try XCTUnwrap(written.first)
        let payload = try Self.readEmbeddedMetadata(at: image.path)
        XCTAssertEqual(payload["prompt"] as? String, "make it green")
        XCTAssertEqual(payload["model"] as? String, request.model)
        XCTAssertEqual(payload["seed"] as? String, "7")
        XCTAssertEqual(payload["toolVersion"] as? String, Configuration.toolVersion)
    }

    // MARK: - Request augmentation

    func testEditPassesImageBytesToProvider() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let inputURL = try Self.writePNG(in: dir, name: "src.png")
        let originalBytes = try Data(contentsOf: inputURL)
        let pngBytes = try Self.makeSolidPNGData(width: 8, height: 8)
        let request = Self.makeRequest()
        let provider = MockImageProvider(images: [
            Self.makeImage(data: pngBytes, request: request)
        ])

        _ = try await SwiftMageXOrchestrator.edit(
            input: inputURL.path,
            mask: nil,
            request: request,
            output: dir.path,
            provider: provider
        )

        let recorded = try XCTUnwrap(provider.receivedRequests.first)
        XCTAssertEqual(recorded.referenceImages.count, 1)
        XCTAssertEqual(recorded.referenceImages.first?.data, originalBytes)
        XCTAssertEqual(recorded.referenceImages.first?.mimeType, "image/png")
        XCTAssertNil(recorded.mask)
        XCTAssertNil(recorded.maskMimeType)
    }

    func testEditPassesMultipleReferenceImagesToProvider() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let primaryURL = try Self.writePNG(in: dir, name: "primary.png")
        let secondURL = try Self.writePNG(in: dir, name: "ref2.png")
        let thirdURL = try Self.writePNG(in: dir, name: "ref3.png")
        let primaryBytes = try Data(contentsOf: primaryURL)
        let secondBytes = try Data(contentsOf: secondURL)
        let thirdBytes = try Data(contentsOf: thirdURL)
        let pngBytes = try Self.makeSolidPNGData(width: 8, height: 8)
        let request = Self.makeRequest(prompt: "merge subject from primary into scene 2")
        let provider = MockImageProvider(images: [
            Self.makeImage(data: pngBytes, request: request)
        ])

        _ = try await SwiftMageXOrchestrator.edit(
            input: primaryURL.path,
            references: [secondURL.path, thirdURL.path],
            mask: nil,
            request: request,
            output: dir.path,
            provider: provider
        )

        let recorded = try XCTUnwrap(provider.receivedRequests.first)
        XCTAssertEqual(
            recorded.referenceImages.map(\.data),
            [primaryBytes, secondBytes, thirdBytes],
            "Primary input is index 0; --reference values follow in order"
        )
        XCTAssertEqual(
            recorded.referenceImages.map(\.mimeType),
            ["image/png", "image/png", "image/png"]
        )
    }

    func testEditRejectsMissingReferenceFile() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let primaryURL = try Self.writePNG(in: dir, name: "primary.png")
        let request = Self.makeRequest()
        let provider = MockImageProvider(images: [])

        do {
            _ = try await SwiftMageXOrchestrator.edit(
                input: primaryURL.path,
                references: [dir.appendingPathComponent("missing-ref.png").path],
                mask: nil,
                request: request,
                output: dir.path,
                provider: provider
            )
            XCTFail("Expected missing reference file to throw")
        } catch let error as SwiftMageXError {
            guard case .io(let message) = error else {
                return XCTFail("Expected .io, got \(error)")
            }
            XCTAssertTrue(message.contains("reference"), "Error should distinguish reference vs input: \(message)")
        }
        XCTAssertEqual(provider.receivedRequests.count, 0)
    }

    func testEditPassesMaskBytesToProvider() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let inputURL = try Self.writePNG(in: dir, name: "src.png")
        let maskURL = try Self.writePNG(in: dir, name: "mask.png")
        let maskBytes = try Data(contentsOf: maskURL)
        let pngBytes = try Self.makeSolidPNGData(width: 8, height: 8)
        let request = Self.makeRequest()
        let provider = MockImageProvider(images: [
            Self.makeImage(data: pngBytes, request: request)
        ])

        _ = try await SwiftMageXOrchestrator.edit(
            input: inputURL.path,
            mask: maskURL.path,
            request: request,
            output: dir.path,
            provider: provider
        )

        let recorded = try XCTUnwrap(provider.receivedRequests.first)
        XCTAssertEqual(recorded.mask, maskBytes)
        XCTAssertEqual(recorded.maskMimeType, "image/png")
    }

    // MARK: - Validation

    func testEditRejectsImagenModel() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let inputURL = try Self.writePNG(in: dir, name: "src.png")
        let request = Self.makeRequest(model: "imagen-4.0-generate-001")
        let provider = MockImageProvider(images: [])

        do {
            _ = try await SwiftMageXOrchestrator.edit(
                input: inputURL.path,
                mask: nil,
                request: request,
                output: dir.path,
                provider: provider
            )
            XCTFail("Expected Imagen model to be rejected")
        } catch let error as SwiftMageXError {
            guard case .invalidInput = error else {
                return XCTFail("Expected .invalidInput, got \(error)")
            }
            XCTAssertEqual(error.exitCode, 2)
        }
        XCTAssertEqual(provider.receivedRequests.count, 0, "Provider must not be invoked for invalid models")
    }

    func testEditRequiresInputFile() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let request = Self.makeRequest()
        let provider = MockImageProvider(images: [])

        do {
            _ = try await SwiftMageXOrchestrator.edit(
                input: dir.appendingPathComponent("missing.png").path,
                mask: nil,
                request: request,
                output: dir.path,
                provider: provider
            )
            XCTFail("Expected missing input file to throw")
        } catch let error as SwiftMageXError {
            guard case .io = error else {
                return XCTFail("Expected .io, got \(error)")
            }
            XCTAssertEqual(error.exitCode, 1)
        }
    }

    func testEditRejectsUnsupportedInputFormat() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // A plain text file with a .png suffix — ImageFormat.detect inspects
        // the actual content via ImageIO, so this resolves to nil.
        let unsupported = dir.appendingPathComponent("not-an-image.png")
        try Data("hello".utf8).write(to: unsupported)

        let request = Self.makeRequest()
        let provider = MockImageProvider(images: [])

        do {
            _ = try await SwiftMageXOrchestrator.edit(
                input: unsupported.path,
                mask: nil,
                request: request,
                output: dir.path,
                provider: provider
            )
            XCTFail("Expected unsupported format to throw")
        } catch let error as SwiftMageXError {
            guard case .invalidInput = error else {
                return XCTFail("Expected .invalidInput, got \(error)")
            }
            XCTAssertEqual(error.exitCode, 2)
        }
    }

    func testEditRequiresMaskFileWhenSpecified() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let inputURL = try Self.writePNG(in: dir, name: "src.png")
        let request = Self.makeRequest()
        let provider = MockImageProvider(images: [])

        do {
            _ = try await SwiftMageXOrchestrator.edit(
                input: inputURL.path,
                mask: dir.appendingPathComponent("missing-mask.png").path,
                request: request,
                output: dir.path,
                provider: provider
            )
            XCTFail("Expected missing mask to throw")
        } catch let error as SwiftMageXError {
            guard case .io = error else {
                return XCTFail("Expected .io, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    private static func makeRequest(
        prompt: String = "edit me",
        count: Int = 1,
        seed: UInt64? = nil,
        model: String = "gemini-2.5-flash-image"
    ) -> GenerationRequest {
        GenerationRequest(
            prompt: prompt,
            size: .square,
            count: count,
            seed: seed,
            model: model
        )
    }

    private static func makeImage(
        data: Data,
        request: GenerationRequest
    ) -> GeneratedImage {
        GeneratedImage(
            data: data,
            format: .png,
            prompt: request.prompt,
            model: request.model,
            seed: nil
        )
    }

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-edit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func writePNG(in dir: URL, name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let bytes = try makeSolidPNGData(width: 4, height: 4)
        try bytes.write(to: url)
        return url
    }

    private static func makeSolidPNGData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 50
            pixels[i + 1] = 120
            pixels[i + 2] = 200
            pixels[i + 3] = 255
        }
        let cg: CGImage = pixels.withUnsafeMutableBufferPointer { ptr -> CGImage in
            let ctx = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            return ctx.makeImage()!
        }

        let mutable = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutable as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw SwiftMageXError.raster("could not create PNG destination for test fixture")
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw SwiftMageXError.raster("could not finalize PNG fixture")
        }
        return mutable as Data
    }

    private static func readEmbeddedMetadata(at url: URL) throws -> [String: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any],
              let description = png[kCGImagePropertyPNGDescription] as? String else {
            throw SwiftMageXError.io("PNG description missing at \(url.path)")
        }
        guard let data = description.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SwiftMageXError.io("metadata blob was not parseable JSON")
        }
        return parsed
    }
}
