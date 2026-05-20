import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SwiftMageXKit

final class GenerateFlowTests: XCTestCase {
    // MARK: - Tests

    func testGenerateWritesAllImagesToAbsolutePaths() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pngBytes = try Self.makeSolidPNGData(width: 8, height: 8)
        let request = Self.makeRequest(count: 3)
        let provider = MockImageProvider(images: [
            Self.makeImage(data: pngBytes, request: request),
            Self.makeImage(data: pngBytes, request: request),
            Self.makeImage(data: pngBytes, request: request)
        ])

        let urls = try await SwiftMageXOrchestrator.generate(
            request: request,
            output: dir.path,
            provider: provider
        )

        XCTAssertEqual(urls.count, 3)
        for url in urls {
            XCTAssertTrue(url.path.hasPrefix("/"), "Path must be absolute: \(url.path)")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "File should exist at \(url.path)"
            )
            XCTAssertEqual(Self.formatOfFile(at: url), .png)
        }
    }

    func testGenerateEmbedsPromptAndModelInPNGMetadata() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pngBytes = try Self.makeSolidPNGData(width: 8, height: 8)
        let request = Self.makeRequest(
            prompt: "a mountain at sunset",
            count: 1,
            seed: 12345
        )
        let provider = MockImageProvider(images: [
            Self.makeImage(data: pngBytes, request: request)
        ])

        let urls = try await SwiftMageXOrchestrator.generate(
            request: request,
            output: dir.path,
            provider: provider
        )

        let url = try XCTUnwrap(urls.first)
        let payload = try Self.readEmbeddedMetadata(at: url, format: .png)

        XCTAssertEqual(payload["prompt"] as? String, "a mountain at sunset")
        XCTAssertEqual(payload["model"] as? String, request.model)
        XCTAssertEqual(payload["seed"] as? String, "12345")
        XCTAssertEqual(payload["toolVersion"] as? String, Configuration.toolVersion)
        XCTAssertNotNil(payload["timestamp"] as? String)
    }

    func testGenerateRecordsSeedEvenWhenProviderDoesNotSupportIt() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pngBytes = try Self.makeSolidPNGData(width: 8, height: 8)
        let request = Self.makeRequest(seed: 9999)
        // A provider whose capabilities say seeds are not supported, and whose
        // returned GeneratedImage carries seed=nil.
        let provider = MockImageProvider(
            capabilities: .init(supportsSeed: false, maxBatchSize: 4, supportedSizes: ImageSize.allCases),
            images: [Self.makeImage(data: pngBytes, request: request, seed: nil)]
        )

        let urls = try await SwiftMageXOrchestrator.generate(
            request: request,
            output: dir.path,
            provider: provider
        )

        let url = try XCTUnwrap(urls.first)
        let payload = try Self.readEmbeddedMetadata(at: url, format: .png)
        // Spec §12: write the seed as recorded intent even when the provider
        // ignored it.
        XCTAssertEqual(payload["seed"] as? String, "9999")
    }

    func testGenerateRequiresAPIKey() async {
        let request = Self.makeRequest()

        do {
            _ = try await SwiftMageXOrchestrator.generate(
                request: request,
                output: nil,
                environment: [:]
            )
            XCTFail("Expected missing API key to throw")
        } catch let error as SwiftMageXError {
            guard case .configuration = error else {
                return XCTFail("Expected .configuration, got \(error)")
            }
            XCTAssertEqual(error.exitCode, 4)
        } catch {
            XCTFail("Expected SwiftMageXError, got \(error)")
        }
    }

    func testGenerateFailsWhenProviderReturnsNoImages() async {
        let provider = MockImageProvider(images: [])
        do {
            _ = try await SwiftMageXOrchestrator.generate(
                request: Self.makeRequest(),
                output: nil,
                provider: provider
            )
            XCTFail("Expected empty provider response to throw")
        } catch let error as SwiftMageXError {
            guard case .provider = error else {
                return XCTFail("Expected .provider, got \(error)")
            }
        } catch {
            XCTFail("Expected SwiftMageXError, got \(error)")
        }
    }

    // MARK: - Helpers

    private static func makeRequest(
        prompt: String = "anything",
        count: Int = 1,
        seed: UInt64? = nil
    ) -> GenerationRequest {
        GenerationRequest(
            prompt: prompt,
            size: .square,
            count: count,
            seed: seed,
            model: "gemini-2.5-flash-image"
        )
    }

    private static func makeImage(
        data: Data,
        request: GenerationRequest,
        seed: UInt64? = nil
    ) -> GeneratedImage {
        GeneratedImage(
            data: data,
            format: .png,
            prompt: request.prompt,
            model: request.model,
            seed: seed
        )
    }

    private static func makeSolidPNGData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 200
            pixels[i + 1] = 80
            pixels[i + 2] = 80
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

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-generate-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func formatOfFile(at url: URL) -> ImageFormat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let rawUTI = CGImageSourceGetType(source) as String? else {
            return nil
        }
        guard let type = UTType(rawUTI) else { return nil }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .jpeg) { return .jpeg }
        return nil
    }

    /// Reads the JSON-packed metadata payload written by the orchestrator.
    /// For PNG that lives in the standard `Description` text slot; for JPEG it
    /// lives in `ExifUserComment`. ImageIO only round-trips a fixed set of
    /// documented PNG dictionary keys, which is why we pack into the standard
    /// slot rather than scattering across custom keys.
    private static func readEmbeddedMetadata(
        at url: URL,
        format: ImageFormat
    ) throws -> [String: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw SwiftMageXError.io("could not read properties at \(url.path)")
        }
        let blob: String
        switch format {
        case .png:
            guard let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any],
                  let description = png[kCGImagePropertyPNGDescription] as? String else {
                throw SwiftMageXError.io("PNG description missing at \(url.path)")
            }
            blob = description
        case .jpeg:
            guard let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
                  let comment = exif[kCGImagePropertyExifUserComment] as? String else {
                throw SwiftMageXError.io("JPEG UserComment missing at \(url.path)")
            }
            blob = comment
        }
        guard let data = blob.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SwiftMageXError.io("metadata blob was not parseable JSON")
        }
        return parsed
    }
}
