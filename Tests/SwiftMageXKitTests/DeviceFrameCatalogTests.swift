import Foundation
import XCTest
@testable import SwiftMageXKit

/// Verifies that the bundled device-frame manifest decodes correctly and that
/// every entry's PNG is reachable through `Bundle.module`. Lives in the kit's
/// test target because that target shares the kit's resource bundle.
final class DeviceFrameCatalogTests: XCTestCase {
    func testManifestLoadsAndIsNonEmpty() throws {
        let frames = try DeviceFrameCatalog.load(bundle: DeviceFrameCatalog.resourceBundle)
        XCTAssertFalse(
            frames.isEmpty,
            "the bundled frames manifest should ship with at least one frame"
        )
    }

    func testEveryFrameResolvesAResourceURL() throws {
        // The cached singleton is what the orchestrator reaches for at runtime,
        // so we drive the same code path the production resolver uses.
        for frame in DeviceFrameCatalog.all {
            let url = try frame.resolveURL(in: DeviceFrameCatalog.resourceBundle)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "frame '\(frame.id)' resource URL does not exist on disk: \(url.path)"
            )
        }
    }

    func testFrameIDsAreUnique() {
        let ids = DeviceFrameCatalog.all.map(\.id)
        XCTAssertEqual(
            Set(ids).count,
            ids.count,
            "frames.json contains duplicate ids: \(ids)"
        )
    }

    func testLookupByIDRoundTrips() {
        for frame in DeviceFrameCatalog.all {
            XCTAssertEqual(
                DeviceFrameCatalog.frame(id: frame.id)?.id,
                frame.id
            )
        }
        XCTAssertNil(
            DeviceFrameCatalog.frame(id: "definitely-not-a-real-frame"),
            "unknown ids must resolve to nil so the orchestrator can fall through to path handling"
        )
    }

    func testDefaultFrameMatchesPommePlateMapping() {
        // Sanity-check the one frame we vendor right now. When a new device
        // gets bundled art, add a corresponding assertion here.
        let defaultForSixFive = DeviceFrameCatalog.defaultFrame(for: "iphone-6.5")
        XCTAssertNotNil(
            defaultForSixFive,
            "iphone-6.5 must have a bundled frame (the PommePlate XS Max / 11 Pro Max)"
        )
        XCTAssertEqual(defaultForSixFive?.deviceID, "iphone-6.5")
        XCTAssertEqual(defaultForSixFive?.license, "CC0-1.0")
    }

    func testNoBundledFrameForUnsupportedDevice() {
        // Auto-pick stays off for slots we haven't shipped art for yet — that
        // way `appstore --device iphone-6.9` without `--frame` preserves the
        // pre-bundle behaviour (skip framing).
        XCTAssertNil(DeviceFrameCatalog.defaultFrame(for: "iphone-6.9"))
        XCTAssertNil(DeviceFrameCatalog.defaultFrame(for: "iphone-5.5"))
    }
}
