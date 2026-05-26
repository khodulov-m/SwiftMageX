import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SwiftMageXKit

/// End-to-end coverage of the App Store screenshot pipeline through the
/// orchestrator — pure local raster work, no API key required.
final class AppStoreFlowTests: XCTestCase {
    func testPrepareScreenshotsWithFrameAndCaption() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let screenshot = try writeColorPNG(dir, "shot.png", width: 120, height: 260, r: 30, g: 160, b: 90)
        let background = try writeColorPNG(dir, "bg.png", width: 400, height: 400, r: 10, g: 20, b: 40)
        let frame = try writeFramePNG(dir, "frame.png", width: 140, height: 300, margin: 8,
                                      hole: (x: 20, y: 30, w: 100, h: 240))

        let outDir = dir.appendingPathComponent("out", isDirectory: true)
        let devices = try ASCDeviceCatalog.sizes(for: ["iphone-6.9", "iphone-5.5"])

        let caption = TextSpec(
            text: "Plan your week",
            position: .bottom,
            fontName: nil,
            fontSize: 64,
            color: "#FFFFFF",
            strokeColor: nil,
            strokeWidth: 0
        )

        let written = try SwiftMageXOrchestrator.prepareAppStoreScreenshots(
            screenshot: screenshot.path,
            background: background.path,
            frame: frame.path,
            caption: caption,
            devices: devices,
            placement: CompositeSpec(position: .center, scale: 0.85),
            output: outDir.path
        )

        XCTAssertEqual(written.count, 2)
        XCTAssertEqual(written[0].width, 1290)
        XCTAssertEqual(written[0].height, 2796)
        XCTAssertEqual(written[1].width, 1242)
        XCTAssertEqual(written[1].height, 2208)
        for image in written {
            XCTAssertTrue(image.path.path.hasPrefix("/"), "paths must be absolute: \(image.path.path)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: image.path.path))
            XCTAssertTrue(image.path.lastPathComponent.hasPrefix("appstore_"))
        }
        // Filenames encode the device id and pixel size.
        XCTAssertEqual(written[0].path.lastPathComponent, "appstore_iphone-6.9_1290x2796.png")
        XCTAssertEqual(written[1].path.lastPathComponent, "appstore_iphone-5.5_1242x2208.png")
    }

    func testPrepareScreenshotsWithoutFrame() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let screenshot = try writeColorPNG(dir, "shot.png", width: 100, height: 200, r: 200, g: 0, b: 0)
        let background = try writeColorPNG(dir, "bg.png", width: 300, height: 600, r: 0, g: 0, b: 0)

        let written = try SwiftMageXOrchestrator.prepareAppStoreScreenshots(
            screenshot: screenshot.path,
            background: background.path,
            frame: nil,
            caption: nil,
            devices: try ASCDeviceCatalog.sizes(for: ["iphone-5.5"]),
            placement: CompositeSpec(scale: 0.8),
            output: dir.path
        )
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written[0].width, 1242)
        XCTAssertEqual(written[0].height, 2208)
    }

    func testBundledFrameIdResolvesToVendoredArt() throws {
        // `frame:` accepts a bundled frame id (no path on disk). The
        // orchestrator should resolve it through `DeviceFrameCatalog` and
        // produce a framed device just like a path argument would. We can't
        // pixel-diff the result here, but we can assert that:
        //   - the pipeline succeeds end-to-end with the real CC0 asset
        //   - the output dimensions still match the requested ASC slot
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let screenshot = try writeColorPNG(dir, "shot.png", width: 200, height: 400, r: 0, g: 120, b: 200)
        let background = try writeColorPNG(dir, "bg.png", width: 400, height: 400, r: 30, g: 30, b: 30)

        let bundled = try XCTUnwrap(
            DeviceFrameCatalog.frame(id: "iphone-6.5-pommeplate-spacegray"),
            "bundled frame must be present in the catalog"
        )
        XCTAssertEqual(bundled.license, "CC0-1.0")

        let written = try SwiftMageXOrchestrator.prepareAppStoreScreenshots(
            screenshot: screenshot.path,
            background: background.path,
            frame: bundled.id,
            caption: nil,
            devices: try ASCDeviceCatalog.sizes(for: ["iphone-6.5"]),
            placement: CompositeSpec(position: .center, scale: 0.85),
            output: dir.path
        )
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written[0].width, 1242)
        XCTAssertEqual(written[0].height, 2688)
        XCTAssertTrue(FileManager.default.fileExists(atPath: written[0].path.path))
    }

    func testAutoPickFrameForKnownDeviceWithoutFrameArg() throws {
        // When the caller omits `--frame` and the first device has a bundled
        // bezel, the orchestrator should auto-pick it. The smoke-test here is
        // that the pipeline completes — auto-pick failure would surface as an
        // unhandled error from the catalog resolver.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let screenshot = try writeColorPNG(dir, "shot.png", width: 200, height: 400, r: 200, g: 80, b: 80)
        let background = try writeColorPNG(dir, "bg.png", width: 400, height: 400, r: 0, g: 0, b: 0)

        let written = try SwiftMageXOrchestrator.prepareAppStoreScreenshots(
            screenshot: screenshot.path,
            background: background.path,
            frame: nil,
            caption: nil,
            devices: try ASCDeviceCatalog.sizes(for: ["iphone-6.5"]),
            placement: CompositeSpec(scale: 0.85),
            output: dir.path
        )
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written[0].width, 1242)
        XCTAssertEqual(written[0].height, 2688)
    }

    func testUnknownFrameIdSurfacesAsIOError() {
        // A non-empty `frame:` that's neither a known id nor a real path on
        // disk must surface as `.io` so the frontend reports the missing input
        // with the same exit-code 5 category as before — *not* as a silently
        // ignored value.
        XCTAssertThrowsError(try SwiftMageXOrchestrator.prepareAppStoreScreenshots(
            screenshot: "/tmp/whatever.png",
            background: "/tmp/whatever.png",
            frame: "iphone-99-bogus",
            caption: nil,
            devices: try ASCDeviceCatalog.sizes(for: ["iphone-6.5"]),
            placement: CompositeSpec(),
            output: nil
        )) { error in
            guard let smx = error as? SwiftMageXError, case .io = smx else {
                return XCTFail("Expected SwiftMageXError.io for unknown frame id / non-existent file, got \(error)")
            }
        }
    }

    func testMissingScreenshotThrowsIO() {
        XCTAssertThrowsError(try SwiftMageXOrchestrator.prepareAppStoreScreenshots(
            screenshot: "/tmp/does-not-exist-\(UUID().uuidString).png",
            background: "/tmp/also-missing.png",
            frame: nil,
            caption: nil,
            devices: ASCDeviceCatalog.all,
            placement: CompositeSpec(),
            output: nil
        )) { error in
            guard let smx = error as? SwiftMageXError, case .io = smx else {
                return XCTFail("Expected SwiftMageXError.io, got \(error)")
            }
        }
    }

    // MARK: - Fixtures

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-appstore-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeColorPNG(_ dir: URL, _ name: String, width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let image = CoreImageRasterEngine()
        try image.write(
            RasterImage(cgImage: Self.solid(width: width, height: height, r: r, g: g, b: b)),
            to: url, format: .png, quality: 1.0, metadata: nil
        )
        return url
    }

    private func writeFramePNG(_ dir: URL, _ name: String, width: Int, height: Int, margin: Int, hole: (x: Int, y: Int, w: Int, h: Int)) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try CoreImageRasterEngine().write(
            RasterImage(cgImage: Self.frame(width: width, height: height, margin: margin, hole: hole)),
            to: url, format: .png, quality: 1.0, metadata: nil
        )
        return url
    }

    private static func solid(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bpr = width * 4
        var bytes = [UInt8](repeating: 0, count: bpr * height)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255
        }
        let ctx = bytes.withUnsafeMutableBufferPointer { ptr in
            CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: bpr, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        return ctx.makeImage()!
    }

    private static func frame(width: Int, height: Int, margin: Int, hole: (x: Int, y: Int, w: Int, h: Int)) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bpr = width * 4
        var bytes = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let inBezel = x >= margin && x < width - margin && y >= margin && y < height - margin
                let inHole = x >= hole.x && x < hole.x + hole.w && y >= hole.y && y < hole.y + hole.h
                guard inBezel && !inHole else { continue }
                let i = y * bpr + x * 4
                bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 255
            }
        }
        let ctx = bytes.withUnsafeMutableBufferPointer { ptr in
            CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: bpr, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        return ctx.makeImage()!
    }
}
