import Foundation
import XCTest
@testable import SwiftMageXKit

final class ResponseCacheTests: XCTestCase {
    // MARK: - Key determinism

    func testIdenticalRequestsProduceIdenticalKeys() {
        let a = Self.makeRequest(prompt: "a fox", seed: 7)
        let b = Self.makeRequest(prompt: "a fox", seed: 7)
        XCTAssertEqual(CacheKey.compute(from: a), CacheKey.compute(from: b))
    }

    func testKeyChangesWhenAnyMaterialFieldChanges() {
        let base = Self.makeRequest()
        let prompts = Self.makeRequest(prompt: "different")
        let counts = Self.makeRequest(count: 2)
        let seeds = Self.makeRequest(seed: 1)
        let sizes = Self.makeRequest(size: .portrait)
        let models = Self.makeRequest(model: "gemini-3-pro-image-preview")

        let baseKey = CacheKey.compute(from: base)
        XCTAssertNotEqual(baseKey, CacheKey.compute(from: prompts))
        XCTAssertNotEqual(baseKey, CacheKey.compute(from: counts))
        XCTAssertNotEqual(baseKey, CacheKey.compute(from: seeds))
        XCTAssertNotEqual(baseKey, CacheKey.compute(from: sizes))
        XCTAssertNotEqual(baseKey, CacheKey.compute(from: models))
    }

    func testKeyHashesReferenceImageBytes() {
        let bytesA = Data([0x01, 0x02, 0x03])
        let bytesB = Data([0x04, 0x05, 0x06])
        let refA = ReferenceImage(data: bytesA, mimeType: "image/png")
        let refB = ReferenceImage(data: bytesB, mimeType: "image/png")

        let withA = Self.makeRequest(referenceImages: [refA])
        let withB = Self.makeRequest(referenceImages: [refB])

        XCTAssertNotEqual(CacheKey.compute(from: withA), CacheKey.compute(from: withB))
    }

    func testKeyHashesMaskBytes() {
        let withMask1 = Self.makeRequest(mask: Data([0xAA]))
        let withMask2 = Self.makeRequest(mask: Data([0xBB]))
        let withoutMask = Self.makeRequest()

        XCTAssertNotEqual(CacheKey.compute(from: withMask1), CacheKey.compute(from: withMask2))
        XCTAssertNotEqual(CacheKey.compute(from: withMask1), CacheKey.compute(from: withoutMask))
    }

    // MARK: - Filesystem cache

    func testStoreThenLookupRoundtrip() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileSystemResponseCache(directory: dir)
        let key = "deadbeef"
        let payload = CachedResponse(images: [
            CachedImage(data: Data("png-bytes-0".utf8), format: .png),
            CachedImage(data: Data("png-bytes-1".utf8), format: .png)
        ])

        try cache.store(key, response: payload)
        let hit = try XCTUnwrap(try cache.lookup(key))
        XCTAssertEqual(hit, payload)
    }

    func testLookupMissReturnsNil() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileSystemResponseCache(directory: dir)
        XCTAssertNil(try cache.lookup("nope"))
    }

    func testLookupOnCorruptedMetaJsonThrows() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Forge an entry directory whose meta.json is unparseable. The cache
        // surfaces this as `throws` (not as a silent miss); the orchestrator
        // wraps `lookup` in `try?` so the user-facing effect is still
        // graceful — verified separately in the flow tests.
        let entry = dir.appendingPathComponent("badkey", isDirectory: true)
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: entry.appendingPathComponent("meta.json"))

        let cache = FileSystemResponseCache(directory: dir)
        XCTAssertThrowsError(try cache.lookup("badkey"))
    }

    func testStoreCreatesParentDirectoryLazily() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-cache-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        // Deliberately do NOT create `parent` ahead of time — the cache
        // should treat a missing directory as a first-use signal, not an
        // error.
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.path))

        let cache = FileSystemResponseCache(directory: parent)
        try cache.store("k", response: CachedResponse(images: [
            CachedImage(data: Data([0x00]), format: .png)
        ]))

        XCTAssertTrue(FileManager.default.fileExists(atPath: parent.path))
        XCTAssertNotNil(try cache.lookup("k"))
    }

    func testStoreIsIdempotentWhenEntryAlreadyExists() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileSystemResponseCache(directory: dir)
        let first = CachedResponse(images: [CachedImage(data: Data("v1".utf8), format: .png)])
        let second = CachedResponse(images: [CachedImage(data: Data("v2".utf8), format: .png)])

        try cache.store("k", response: first)
        try cache.store("k", response: second)

        let hit = try XCTUnwrap(try cache.lookup("k"))
        // Content addressing means a key is satisfied by *any* valid entry —
        // the second store is a no-op, so the original bytes survive. Tests
        // pin this so an accidental "overwrite on store" regression is loud.
        XCTAssertEqual(hit, first)
    }

    // MARK: - Helpers

    private static func makeRequest(
        prompt: String = "anything",
        size: ImageSize = .square,
        count: Int = 1,
        seed: UInt64? = nil,
        model: String = "gemini-2.5-flash-image",
        referenceImages: [ReferenceImage] = [],
        mask: Data? = nil
    ) -> GenerationRequest {
        GenerationRequest(
            prompt: prompt,
            size: size,
            count: count,
            seed: seed,
            model: model,
            referenceImages: referenceImages,
            mask: mask,
            maskMimeType: mask == nil ? nil : "image/png"
        )
    }

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmagex-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
