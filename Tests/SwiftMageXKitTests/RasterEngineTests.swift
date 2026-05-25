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

    // MARK: - Text overlay

    func testTextOverlayWritesExpectedDimensions() throws {
        let engine = CoreImageRasterEngine()
        let source = RasterImage(cgImage: Self.makeSolidImage(width: 400, height: 200))
        let spec = TextSpec(
            text: "Hello",
            position: .bottom,
            fontName: nil,
            fontSize: 24,
            color: "#FFFFFF",
            strokeColor: nil,
            strokeWidth: 0
        )
        let result = try engine.overlayText(source, spec)
        XCTAssertEqual(result.width, 400)
        XCTAssertEqual(result.height, 200)
    }

    func testTextOverlayWithStrokeProducesDifferentBytesThanWithoutStroke() throws {
        let engine = CoreImageRasterEngine()
        let source = RasterImage(cgImage: Self.makeSolidImage(width: 400, height: 200))
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bare = try engine.overlayText(
            source,
            TextSpec(
                text: "SALE",
                position: .center,
                fontName: nil,
                fontSize: 48,
                color: "#FFFFFF",
                strokeColor: nil,
                strokeWidth: 0
            )
        )
        let stroked = try engine.overlayText(
            source,
            TextSpec(
                text: "SALE",
                position: .center,
                fontName: nil,
                fontSize: 48,
                color: "#FFFFFF",
                strokeColor: "#000000",
                strokeWidth: 4
            )
        )

        let bareURL = dir.appendingPathComponent("bare.png")
        let strokedURL = dir.appendingPathComponent("stroked.png")
        try engine.write(bare, to: bareURL, format: .png, quality: 1.0, metadata: nil)
        try engine.write(stroked, to: strokedURL, format: .png, quality: 1.0, metadata: nil)

        let a = try Data(contentsOf: bareURL)
        let b = try Data(contentsOf: strokedURL)
        XCTAssertNotEqual(a, b, "expected stroke parameter to influence the rendered bytes")
    }

    func testInvalidHexColorThrowsInvalidInput() throws {
        let engine = CoreImageRasterEngine()
        let source = RasterImage(cgImage: Self.makeSolidImage(width: 100, height: 100))
        let spec = TextSpec(
            text: "x",
            position: .center,
            fontName: nil,
            fontSize: 12,
            color: "#ZZZ",
            strokeColor: nil,
            strokeWidth: 0
        )
        XCTAssertThrowsError(try engine.overlayText(source, spec)) { error in
            guard let smx = error as? SwiftMageXError, case .invalidInput = smx else {
                return XCTFail("Expected SwiftMageXError.invalidInput, got \(error)")
            }
        }
    }

    func testInvalidStrokeHexColorThrowsInvalidInput() throws {
        let engine = CoreImageRasterEngine()
        let source = RasterImage(cgImage: Self.makeSolidImage(width: 100, height: 100))
        let spec = TextSpec(
            text: "x",
            position: .center,
            fontName: nil,
            fontSize: 12,
            color: "#FFFFFF",
            strokeColor: "not-a-hex",
            strokeWidth: 1
        )
        XCTAssertThrowsError(try engine.overlayText(source, spec)) { error in
            guard let smx = error as? SwiftMageXError, case .invalidInput = smx else {
                return XCTFail("Expected SwiftMageXError.invalidInput, got \(error)")
            }
        }
    }

    // MARK: - Composite

    func testCompositeKeepsBackgroundDimensions() throws {
        let engine = CoreImageRasterEngine()
        let bg = RasterImage(cgImage: Self.makeColorImage(width: 200, height: 120, r: 200, g: 0, b: 0))
        let fg = RasterImage(cgImage: Self.makeColorImage(width: 40, height: 40, r: 0, g: 200, b: 0))
        let out = try engine.composite(fg, onto: bg, CompositeSpec(position: .center, scale: 0.25))
        XCTAssertEqual(out.width, 200)
        XCTAssertEqual(out.height, 120)
    }

    func testCompositePlacesForegroundAtAnchor() throws {
        let engine = CoreImageRasterEngine()
        // Red background, green foreground fit into a 0.25 box → ~50×50,
        // centered on the 200×200 canvas at (75,75)–(125,125).
        let bg = RasterImage(cgImage: Self.makeColorImage(width: 200, height: 200, r: 200, g: 0, b: 0))
        let fg = RasterImage(cgImage: Self.makeColorImage(width: 50, height: 50, r: 0, g: 200, b: 0))
        let out = try engine.composite(fg, onto: bg, CompositeSpec(position: .center, scale: 0.25))

        let center = try XCTUnwrap(Self.rgba(of: out.cgImage, x: 100, y: 100))
        XCTAssertGreaterThan(Int(center.g), 100, "center should show the green foreground")
        XCTAssertLessThan(Int(center.r), 80, "center should not be the red background")

        let corner = try XCTUnwrap(Self.rgba(of: out.cgImage, x: 5, y: 5))
        XCTAssertGreaterThan(Int(corner.r), 150, "corner should remain the red background")
        XCTAssertLessThan(Int(corner.g), 80, "corner should not show the foreground")
    }

    func testCompositeRejectsNonPositiveScale() {
        let engine = CoreImageRasterEngine()
        let bg = RasterImage(cgImage: Self.makeColorImage(width: 10, height: 10, r: 1, g: 1, b: 1))
        let fg = RasterImage(cgImage: Self.makeColorImage(width: 4, height: 4, r: 2, g: 2, b: 2))
        XCTAssertThrowsError(try engine.composite(fg, onto: bg, CompositeSpec(scale: 0))) { error in
            guard let smx = error as? SwiftMageXError, case .invalidInput = smx else {
                return XCTFail("Expected SwiftMageXError.invalidInput, got \(error)")
            }
        }
    }

    // MARK: - Remove background

    func testRemoveBackgroundCutoutCarriesAlphaOrReportsNoSubject() throws {
        let engine = CoreImageRasterEngine()
        let source = RasterImage(cgImage: Self.makeBlobImage(width: 200, height: 200))

        // Vision's segmentation model is trained on photos; a synthetic blob may
        // or may not register as salient. Both outcomes are valid for a generated
        // fixture, so accept either a real cutout or a no-subject raster error —
        // the point is that the pipeline runs and maps failures correctly.
        do {
            let result = try engine.removeBackground(source)
            XCTAssertEqual(result.width, 200)
            XCTAssertEqual(result.height, 200)
            let alpha = result.cgImage.alphaInfo
            XCTAssertFalse(
                alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast,
                "a background cutout must carry an alpha channel, got \(alpha.rawValue)"
            )
        } catch let error as SwiftMageXError {
            guard case .raster = error else {
                throw error
            }
        }
    }

    // MARK: - Device framing

    func testDetectScreenRectFindsEnclosedHole() throws {
        // 100×200 frame: 10px transparent margin, opaque blue bezel, a
        // transparent hole near the top at (20,20) sized 60×40.
        let frame = Self.makeFrameImage(
            width: 100, height: 200, margin: 10,
            hole: (x: 20, y: 20, w: 60, h: 40),
            bezel: (0, 0, 255)
        )
        let rect = try XCTUnwrap(
            CoreImageRasterEngine.detectScreenRect(in: frame, alphaThreshold: 16)
        )
        XCTAssertEqual(rect.x, 20)
        XCTAssertEqual(rect.y, 20)
        XCTAssertEqual(rect.width, 60)
        XCTAssertEqual(rect.height, 40)
    }

    func testDetectScreenRectReturnsNilForOpaqueFrame() {
        let opaque = Self.makeColorImage(width: 40, height: 40, r: 10, g: 10, b: 10)
        XCTAssertNil(CoreImageRasterEngine.detectScreenRect(in: opaque, alphaThreshold: 16))
    }

    func testFrameScreenshotPlacesScreenshotInHole() throws {
        let engine = CoreImageRasterEngine()
        let frame = RasterImage(cgImage: Self.makeFrameImage(
            width: 100, height: 200, margin: 10,
            hole: (x: 20, y: 20, w: 60, h: 40),
            bezel: (0, 0, 255)
        ))
        // Gray screenshot so the hole reads gray, distinct from the blue bezel
        // and the transparent surround.
        let shot = RasterImage(cgImage: Self.makeColorImage(width: 120, height: 80, r: 128, g: 128, b: 128))

        let framed = try engine.frameScreenshot(shot, in: frame, DeviceFrameSpec())
        XCTAssertEqual(framed.width, 100)
        XCTAssertEqual(framed.height, 200)

        // Inside the hole → screenshot (gray, high red channel).
        let hole = try XCTUnwrap(Self.rgba(of: framed.cgImage, x: 40, y: 35))
        XCTAssertGreaterThan(Int(hole.r), 100, "hole should reveal the gray screenshot")
        XCTAssertEqual(Int(hole.a), 255, "hole pixel should be opaque")

        // Bezel area below the hole → blue (low red, high blue).
        let bezel = try XCTUnwrap(Self.rgba(of: framed.cgImage, x: 50, y: 120))
        XCTAssertLessThan(Int(bezel.r), 60, "bezel should stay blue, not gray")
        XCTAssertGreaterThan(Int(bezel.b), 180)

        // Outer margin → transparent.
        let margin = try XCTUnwrap(Self.rgba(of: framed.cgImage, x: 2, y: 2))
        XCTAssertLessThan(Int(margin.a), 16, "outer margin should stay transparent")
    }

    func testFrameScreenshotHonorsExplicitScreenRect() throws {
        let engine = CoreImageRasterEngine()
        let opaqueFrame = RasterImage(cgImage: Self.makeColorImage(width: 80, height: 80, r: 0, g: 0, b: 255))
        let shot = RasterImage(cgImage: Self.makeColorImage(width: 40, height: 40, r: 128, g: 128, b: 128))
        // No transparent hole to auto-detect, so this must use the explicit rect
        // (and would throw otherwise).
        let spec = DeviceFrameSpec(screenRect: .init(x: 10, y: 10, width: 20, height: 20))
        let framed = try engine.frameScreenshot(shot, in: opaqueFrame, spec)
        XCTAssertEqual(framed.width, 80)
        XCTAssertEqual(framed.height, 80)
    }

    func testFrameScreenshotThrowsWhenNoHoleAndNoRect() {
        let engine = CoreImageRasterEngine()
        let opaqueFrame = RasterImage(cgImage: Self.makeColorImage(width: 40, height: 40, r: 0, g: 0, b: 255))
        let shot = RasterImage(cgImage: Self.makeColorImage(width: 20, height: 20, r: 1, g: 1, b: 1))
        XCTAssertThrowsError(try engine.frameScreenshot(shot, in: opaqueFrame, DeviceFrameSpec())) { error in
            guard let smx = error as? SwiftMageXError, case .invalidInput = smx else {
                return XCTFail("Expected SwiftMageXError.invalidInput, got \(error)")
            }
        }
    }

    // MARK: - OutputPath.resolveNamed

    func testResolveNamedBuildsAbsolutePerNamePaths() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let urls = try OutputPath.resolveNamed(
            target: dir.path,
            names: ["appstore_iphone-6.9_1290x2796", "appstore_iphone-5.5_1242x2208"],
            format: .png
        )
        XCTAssertEqual(urls.map(\.lastPathComponent), [
            "appstore_iphone-6.9_1290x2796.png",
            "appstore_iphone-5.5_1242x2208.png",
        ])
        for url in urls {
            XCTAssertTrue(url.path.hasPrefix(dir.path), "expected absolute path under \(dir.path)")
        }
    }

    func testResolveNamedRejectsFileTarget() {
        XCTAssertThrowsError(
            try OutputPath.resolveNamed(target: "out.png", names: ["a"], format: .png)
        ) { error in
            guard let smx = error as? SwiftMageXError, case .invalidInput = smx else {
                return XCTFail("Expected SwiftMageXError.invalidInput, got \(error)")
            }
        }
    }

    func testRemoveBackgroundMissingFileThrowsIO() {
        let missing = "/tmp/swiftmagex-tests-does-not-exist-\(UUID().uuidString).png"
        XCTAssertThrowsError(
            try SwiftMageXOrchestrator.removeBackground(input: missing, output: nil)
        ) { error in
            guard let smx = error as? SwiftMageXError, case .io = smx else {
                return XCTFail("Expected SwiftMageXError.io, got \(error)")
            }
        }
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

    /// Solid-color opaque image.
    private static func makeColorImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r
            bytes[i + 1] = g
            bytes[i + 2] = b
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

    /// A synthetic device frame: a fully transparent margin, an opaque bezel,
    /// and an enclosed transparent screen hole. Row 0 is the top.
    private static func makeFrameImage(
        width: Int,
        height: Int,
        margin: Int,
        hole: (x: Int, y: Int, w: Int, h: Int),
        bezel: (r: UInt8, g: UInt8, b: UInt8)
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height) // all transparent
        for y in 0..<height {
            for x in 0..<width {
                let inBezelBox = x >= margin && x < width - margin
                    && y >= margin && y < height - margin
                let inHole = x >= hole.x && x < hole.x + hole.w
                    && y >= hole.y && y < hole.y + hole.h
                guard inBezelBox && !inHole else { continue }
                let i = y * bytesPerRow + x * 4
                bytes[i] = bezel.r
                bytes[i + 1] = bezel.g
                bytes[i + 2] = bezel.b
                bytes[i + 3] = 255
            }
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

    /// Reads a single pixel (top-left origin) from `image` as RGBA bytes.
    private static func rgba(of image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        let width = image.width
        let height = image.height
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        let rowBytes = ctx.bytesPerRow
        let p = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        let i = y * rowBytes + x * 4
        return (p[i], p[i + 1], p[i + 2], p[i + 3])
    }

    /// A filled colored ellipse on a contrasting background — a crude stand-in
    /// for a salient subject, used by the remove-background test.
    private static func makeBlobImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Dark background.
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Bright centered ellipse.
        context.setFillColor(CGColor(red: 0.95, green: 0.4, blue: 0.2, alpha: 1))
        let inset = CGFloat(min(width, height)) * 0.2
        context.fillEllipse(in: CGRect(
            x: inset,
            y: inset,
            width: CGFloat(width) - 2 * inset,
            height: CGFloat(height) - 2 * inset
        ))
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
