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

    // MARK: - Output options

    /// Pins the per-model matrix from Google's image-generation guide
    /// (2026-09-30) so a catalog edit that drifts from it is loud.
    func testPerModelOutputOptionMatrix() throws {
        let flash = try XCTUnwrap(ModelCatalog.descriptor(for: "gemini-3.1-flash-image"))
        XCTAssertEqual(flash.aspectRatios, AspectRatio.allCases)
        XCTAssertEqual(flash.resolutions, [.r512, .r1K, .r2K, .r4K])

        let lite = try XCTUnwrap(ModelCatalog.descriptor(for: "gemini-3.1-flash-lite-image"))
        XCTAssertEqual(lite.aspectRatios, AspectRatio.allCases)
        XCTAssertEqual(lite.resolutions, [.r512, .r1K])

        let pro = try XCTUnwrap(ModelCatalog.descriptor(for: "gemini-3-pro-image"))
        XCTAssertEqual(pro.aspectRatios.count, 10)
        XCTAssertFalse(pro.aspectRatios.contains(.r1x8))
        XCTAssertEqual(pro.resolutions, [.r1K, .r2K, .r4K])
    }

    func testAspectRatioParsingToleratesSeparators() {
        XCTAssertEqual(AspectRatio(parsing: "16:9"), .r16x9)
        XCTAssertEqual(AspectRatio(parsing: " 16x9 "), .r16x9)
        XCTAssertEqual(AspectRatio(parsing: "16X9"), .r16x9)
        XCTAssertEqual(AspectRatio(parsing: "4/5"), .r4x5)
        XCTAssertNil(AspectRatio(parsing: "7:3"))
        XCTAssertNil(AspectRatio(parsing: "9:16:1"))
    }

    func testResolutionParsingIsCaseInsensitive() {
        XCTAssertEqual(ImageResolution(parsing: "2k"), .r2K)
        XCTAssertEqual(ImageResolution(parsing: "4K"), .r4K)
        XCTAssertEqual(ImageResolution(parsing: "512"), .r512)
        XCTAssertEqual(ImageResolution(parsing: "512px"), .r512)
        XCTAssertNil(ImageResolution(parsing: "3K"))
        XCTAssertNil(ImageResolution(parsing: "8K"))
    }

    func testSizePresetsMapToExactRatios() {
        XCTAssertEqual(ImageSize.square.aspectRatio, .r1x1)
        XCTAssertEqual(ImageSize.portrait.aspectRatio, .r9x16)
        XCTAssertEqual(ImageSize.landscape.aspectRatio, .r16x9)
    }
}
