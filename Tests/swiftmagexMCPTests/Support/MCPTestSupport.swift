import CoreGraphics
import Foundation
import ImageIO
import MCP
import SwiftMageXKit
import UniformTypeIdentifiers
import os

/// Test double for ``ImageProvider`` — local to the MCP test target since
/// `SwiftMageXKitTests`' MockImageProvider lives in a separate module.
final class StubImageProvider: ImageProvider, @unchecked Sendable {
    let id: String = "stub"
    let capabilities: ProviderCapabilities

    private let result: Result<[GeneratedImage], SwiftMageXError>

    init(images: [GeneratedImage]) {
        self.capabilities = .init(
            supportsSeed: true,
            maxBatchSize: 4,
            supportedSizes: ImageSize.allCases
        )
        self.result = .success(images)
    }

    init(throwing error: SwiftMageXError) {
        self.capabilities = .init(
            supportsSeed: true,
            maxBatchSize: 4,
            supportedSizes: ImageSize.allCases
        )
        self.result = .failure(error)
    }

    func generate(_ request: GenerationRequest) async throws -> [GeneratedImage] {
        try result.get()
    }
}

/// Synthesizes a small solid-color PNG in memory for tests that need real
/// PNG bytes (handler returns image content blocks; resize/overlay need a
/// real file to read).
enum TestPNG {
    static func bytes(width: Int = 8, height: Int = 8) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 200
            pixels[i + 1] = 80
            pixels[i + 2] = 80
            pixels[i + 3] = 255
        }
        let cg: CGImage = pixels.withUnsafeMutableBufferPointer { ptr in
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
            throw NSError(domain: "TestPNG", code: 1)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "TestPNG", code: 2)
        }
        return mutable as Data
    }

    /// Writes a fresh fixture PNG to a unique temp file and returns the URL.
    /// Caller is responsible for cleanup.
    static func writeFixture(width: Int = 8, height: Int = 8) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fixture.png")
        try bytes(width: width, height: height).write(to: url)
        return url
    }
}

/// Pulls the first text content from a `CallTool.Result` so assertions stay
/// readable without case-matching the enum at every site.
extension CallTool.Result {
    var firstText: String? {
        for c in content {
            if case .text(let text, _, _) = c { return text }
        }
        return nil
    }

    var imageContents: [(data: String, mimeType: String)] {
        content.compactMap { c in
            if case .image(let data, let mime, _, _) = c {
                return (data, mime)
            }
            return nil
        }
    }
}
