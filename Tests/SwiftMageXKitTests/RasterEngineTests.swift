import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SwiftMageXKit

final class RasterEngineTests: XCTestCase {
    // MARK: - Resize math

    func testResizeContainPreservesAspectRatio() throws {
        let engine = CoreImageRasterEngine()
        let image = RasterImage(cgImage: Self.makeSolidImage(width: 100, height: 200))
        let resized = try engine.resize(image, to: ResizeSpec(width: 50, height: 50, fit: .contain))
        XCTAssertEqual(resized.width, 25)
        XCTAssertEqual(resized.height, 50)
    }

    func testResizeCoverCropsOverflow() throws {
        let engine = CoreImageRasterEngine()
        let image = RasterImage(cgImage: Self.makeSolidImage(width: 100, height: 200))
        let resized = try engine.resize(image, to: ResizeSpec(width: 50, height: 50, fit: .cover))
        XCTAssertEqual(resized.width, 50)
        XCTAssertEqual(resized.height, 50)
    }

    func testResizeFillIgnoresAspectRatio() throws {
        let engine = CoreImageRasterEngine()
        let image = RasterImage(cgImage: Self.makeSolidImage(width: 100, height: 200))
        let resized = try engine.resize(image, to: ResizeSpec(width: 60, height: 40, fit: .fill))
        XCTAssertEqual(resized.width, 60)
        XCTAssertEqual(resized.height, 40)
    }

    func testResizeComputesMissingDimension() throws {
        let engine = CoreImageRasterEngine()
        let image = RasterImage(cgImage: Self.makeSolidImage(width: 100, height: 200))
        let resized = try engine.resize(image, to: ResizeSpec(width: 50, height: nil, fit: .contain))
        XCTAssertEqual(resized.width, 50)
        XCTAssertEqual(resized.height, 100)
    }

    func testResizeComputesMissingWidth() throws {
        let engine = CoreImageRasterEngine()
        let image = RasterImage(cgImage: Self.makeSolidImage(width: 100, height: 200))
        let resized = try engine.resize(image, to: ResizeSpec(width: nil, height: 100, fit: .contain))
        XCTAssertEqual(resized.width, 50)
        XCTAssertEqual(resized.height, 100)
    }

    // MARK: - Round trips

    func testRoundTripPNG() throws {
        let engine = CoreImageRasterEngine()
        let source = Self.makeSolidImage(width: 64, height: 32)

        // Write the source out as PNG, read it back, resize, write the result.
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("source.png")
        try engine.write(
            RasterImage(cgImage: source),
            to: sourceURL,
            format: .png,
            quality: 1.0,
            metadata: nil
        )

        let loaded = try engine.load(from: sourceURL)
        XCTAssertEqual(loaded.width, 64)
        XCTAssertEqual(loaded.height, 32)

        let resized = try engine.resize(loaded, to: ResizeSpec(width: 32, height: 16, fit: .fill))
        let outURL = dir.appendingPathComponent("out.png")
        try engine.write(resized, to: outURL, format: .png, quality: 1.0, metadata: nil)

        XCTAssertEqual(Self.formatOfFile(at: outURL), .png)
        let reloaded = try engine.load(from: outURL)
        XCTAssertEqual(reloaded.width, 32)
        XCTAssertEqual(reloaded.height, 16)
    }

    func testRoundTripJPEG() throws {
        let engine = CoreImageRasterEngine()
        let source = Self.makeSolidImage(width: 80, height: 80)

        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("source.jpg")
        try engine.write(
            RasterImage(cgImage: source),
            to: sourceURL,
            format: .jpeg,
            quality: 0.8,
            metadata: nil
        )

        XCTAssertEqual(Self.formatOfFile(at: sourceURL), .jpeg)

        let loaded = try engine.load(from: sourceURL)
        let resized = try engine.resize(loaded, to: ResizeSpec(width: 40, height: 40, fit: .contain))
        let outURL = dir.appendingPathComponent("out.jpg")
        try engine.write(resized, to: outURL, format: .jpeg, quality: 0.8, metadata: nil)

        XCTAssertEqual(Self.formatOfFile(at: outURL), .jpeg)
        let reloaded = try engine.load(from: outURL)
        XCTAssertEqual(reloaded.width, 40)
        XCTAssertEqual(reloaded.height, 40)
    }

    // MARK: - I/O failure modes

    func testLoadMissingFileThrowsIO() {
        let engine = CoreImageRasterEngine()
        let missing = URL(fileURLWithPath: "/tmp/swiftmagex-tests-does-not-exist-\(UUID().uuidString).png")
        XCTAssertThrowsError(try engine.load(from: missing)) { error in
            guard let smx = error as? SwiftMageXError, case .io = smx else {
                return XCTFail("Expected SwiftMageXError.io, got \(error)")
            }
        }
    }

    // MARK: - OutputPath helper

    func testOutputPathDirectoryTargetUsesTimestampPattern() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let urls = try OutputPath.resolve(
            target: dir.path,
            count: 3,
            format: .png,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(urls.count, 3)
        for (i, url) in urls.enumerated() {
            XCTAssertTrue(url.path.hasPrefix(dir.path), "expected absolute path under \(dir.path), got \(url.path)")
            XCTAssertTrue(url.lastPathComponent.hasPrefix("swiftmagex_"))
            XCTAssertTrue(url.lastPathComponent.hasSuffix("_\(i + 1).png"))
        }
    }

    func testOutputPathSpecificFileWithCountAddsIndex() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = dir.appendingPathComponent("out.png").path
        let urls = try OutputPath.resolve(
            target: target,
            count: 2,
            format: .png
        )
        XCTAssertEqual(urls.map(\.lastPathComponent), ["out_1.png", "out_2.png"])
        for url in urls {
            XCTAssertTrue(url.path.hasPrefix("/"), "expected absolute path, got \(url.path)")
        }
    }

    func testOutputPathSingleFileTargetReturnsExactName() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = dir.appendingPathComponent("out.png").path
        let urls = try OutputPath.resolve(
            target: target,
            count: 1,
            format: .png
        )
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].lastPathComponent, "out.png")
    }

    // MARK: - Configuration (kept from skeleton)

    func testConfigurationReadsPrimaryAPIKey() {
        let key = Configuration.resolvedAPIKey(in: [
            Configuration.EnvironmentKey.primaryAPIKey: "abc",
            Configuration.EnvironmentKey.fallbackAPIKey: "xyz",
        ])
        XCTAssertEqual(key, "abc")
    }

    func testConfigurationFallsBackToGeminiKey() {
        let key = Configuration.resolvedAPIKey(in: [
            Configuration.EnvironmentKey.fallbackAPIKey: "xyz",
        ])
        XCTAssertEqual(key, "xyz")
    }

    func testConfigurationReturnsNilWhenAbsent() {
        XCTAssertNil(Configuration.resolvedAPIKey(in: [:]))
    }

    // MARK: - Helpers

    private static func makeSolidImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        // Fill with an opaque mid-gray so JPEG round-trips don't degrade to black.
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = 128
            bytes[i + 1] = 128
            bytes[i + 2] = 128
            bytes[i + 3] = 255
        }
        let context = bytes.withUnsafeMutableBufferPointer { ptr -> CGContext in
            CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
        }
        return context.makeImage()!
    }

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-tests-\(UUID().uuidString)", isDirectory: true)
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
}
