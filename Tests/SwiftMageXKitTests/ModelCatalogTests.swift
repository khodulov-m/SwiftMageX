import XCTest
@testable import SwiftMageXKit

final class ModelCatalogTests: XCTestCase {
    func testCatalogIncludesAllRequestedModels() {
        let expected: Set<String> = [
            "gemini-3.1-flash-image",
            "gemini-3.1-flash-lite-image",
            "gemini-3-pro-image",
        ]
        let actual = Set(ModelCatalog.all.map(\.id))
        XCTAssertEqual(actual, expected)
    }

    func testDefaultModelIsListed() {
        XCTAssertNotNil(ModelCatalog.descriptor(for: ModelCatalog.defaultModelID))
    }

    func testFamilyResolutionForKnownModels() {
        for descriptor in ModelCatalog.all {
            XCTAssertEqual(ModelCatalog.family(for: descriptor.id), descriptor.family, descriptor.id)
        }
    }

    /// Retired ids are no longer catalog entries, but `--model` still accepts
    /// them, so the family they route to must stay correct.
    func testFamilyResolutionForRetiredModels() {
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

    func testCatalogAdvertisesOnlyGAModels() {
        for descriptor in ModelCatalog.all {
            XCTAssertFalse(descriptor.isPreview, "\(descriptor.id) is flagged as preview")
            XCTAssertFalse(
                descriptor.id.hasSuffix("-preview"),
                "\(descriptor.id) is a preview alias; list the GA id instead"
            )
        }
    }

    func testRetiredModelsAreNotAdvertised() {
        for id in [
            "gemini-2.5-flash-image",
            "gemini-3-pro-image-preview",
            "gemini-3.1-flash-image-preview",
            "imagen-4.0-generate-001",
            "imagen-4.0-fast-generate-001",
            "imagen-4.0-ultra-generate-001",
        ] {
            XCTAssertNil(ModelCatalog.descriptor(for: id), "\(id) is retired but still listed")
        }
    }

    func testMakeProviderRoutesByFamily() {
        let gemini = SwiftMageXOrchestrator.makeProvider(
            for: ModelCatalog.defaultModelID,
            apiKey: "k"
        )
        XCTAssertEqual(gemini.id, "gemini")

        // Imagen has no catalog entry since the 4.0 family was retired; the
        // prefix heuristic is what keeps `:predict` reachable.
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
