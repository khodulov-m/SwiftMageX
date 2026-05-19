import XCTest
@testable import SwiftMageXKit

final class RasterEngineTests: XCTestCase {
    /// Placeholder — milestone 2 replaces this with real resize / write / overlay
    /// assertions on a reference image.
    func testStubEngineThrowsNotImplementedForResize() throws {
        // TODO(milestone 2): replace with a real CoreImage resize round-trip
        // (input dimensions → output dimensions, format preservation, etc.).
        let engine = CoreImageRasterEngine()
        let cgImage = Self.makeOnePixelImage()
        let image = RasterImage(cgImage: cgImage)

        XCTAssertThrowsError(
            try engine.resize(image, to: ResizeSpec(width: 64, height: 64, fit: .contain))
        ) { error in
            guard let smx = error as? SwiftMageXError, case .raster = smx else {
                return XCTFail("Expected SwiftMageXError.raster, got \(error)")
            }
        }
    }

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

    private static func makeOnePixelImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 255]
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
