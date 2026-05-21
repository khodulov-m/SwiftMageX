import XCTest
@testable import SwiftMageXKit

final class ModelCatalogTests: XCTestCase {
    func testCatalogIncludesAllRequestedModels() {
        let expected: Set<String> = [
            "gemini-2.5-flash-image",
            "gemini-3-pro-image-preview",
            "gemini-3.1-flash-image-preview",
            "imagen-4.0-generate-001",
            "imagen-4.0-fast-generate-001",
            "imagen-4.0-ultra-generate-001",
        ]
        let actual = Set(ModelCatalog.all.map(\.id))
        XCTAssertEqual(actual, expected)
    }

    func testDefaultModelIsListed() {
        XCTAssertNotNil(ModelCatalog.descriptor(for: ModelCatalog.defaultModelID))
    }

    func testFamilyResolutionForKnownModels() {
        XCTAssertEqual(ModelCatalog.family(for: "gemini-2.5-flash-image"), .gemini)
        XCTAssertEqual(ModelCatalog.family(for: "gemini-3-pro-image-preview"), .gemini)
        XCTAssertEqual(ModelCatalog.family(for: "gemini-3.1-flash-image-preview"), .gemini)
        XCTAssertEqual(ModelCatalog.family(for: "imagen-4.0-generate-001"), .imagen)
        XCTAssertEqual(ModelCatalog.family(for: "imagen-4.0-fast-generate-001"), .imagen)
        XCTAssertEqual(ModelCatalog.family(for: "imagen-4.0-ultra-generate-001"), .imagen)
    }

    func testFamilyPrefixFallbackForUnknownIDs() {
        XCTAssertEqual(ModelCatalog.family(for: "imagen-99.0-future-001"), .imagen)
        XCTAssertEqual(ModelCatalog.family(for: "gemini-5-flash-image"), .gemini)
        XCTAssertEqual(ModelCatalog.family(for: "anything-else"), .gemini, "default fallback is gemini")
    }

    func testPreviewFlagSetForPreviewModels() {
        XCTAssertEqual(ModelCatalog.descriptor(for: "gemini-2.5-flash-image")?.isPreview, false)
        XCTAssertEqual(ModelCatalog.descriptor(for: "gemini-3-pro-image-preview")?.isPreview, true)
        XCTAssertEqual(ModelCatalog.descriptor(for: "gemini-3.1-flash-image-preview")?.isPreview, true)
    }

    func testMakeProviderRoutesByFamily() {
        let gemini = SwiftMageXOrchestrator.makeProvider(
            for: "gemini-2.5-flash-image",
            apiKey: "k"
        )
        XCTAssertEqual(gemini.id, "gemini")

        let imagen = SwiftMageXOrchestrator.makeProvider(
            for: "imagen-4.0-generate-001",
            apiKey: "k"
        )
        XCTAssertEqual(imagen.id, "imagen")

        // Unknown id routes by prefix.
        let imagenPrefix = SwiftMageXOrchestrator.makeProvider(
            for: "imagen-99.0-future-001",
            apiKey: "k"
        )
        XCTAssertEqual(imagenPrefix.id, "imagen")
    }
}
