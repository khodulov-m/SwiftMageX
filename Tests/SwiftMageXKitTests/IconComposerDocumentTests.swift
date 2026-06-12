import XCTest
@testable import SwiftMageXKit

/// `icon.json` encoding/decoding plus the pure document assembly in
/// ``IconPackageBuilder`` — the contract with Icon Composer's file format.
final class IconComposerDocumentTests: XCTestCase {
    // MARK: - Encoding

    func testEncodesRealWorldKeySpellings() throws {
        let document = IconComposerDocument(
            fill: .automaticGradient("srgb:0.50000,0.10000,0.60000,1.00000"),
            groups: [
                IconComposerDocument.Group(layers: [
                    IconComposerDocument.Layer(
                        imageName: "badge.png",
                        name: "badge",
                        glass: false,
                        position: IconComposerDocument.Position(
                            scale: 15,
                            translationInPoints: [222.5, 223.25]
                        ),
                        fillSpecializations: [
                            .init(value: .solid("srgb:1.00000,1.00000,1.00000,1.00000")),
                            .init(appearance: "dark", value: .solid("srgb:0.00000,0.00000,0.00000,1.00000")),
                        ]
                    ),
                ]),
            ]
        )

        let json = try XCTUnwrap(String(data: document.jsonData(), encoding: .utf8))
        XCTAssertTrue(json.contains("\"image-name\""))
        XCTAssertTrue(json.contains("\"translation-in-points\""))
        XCTAssertTrue(json.contains("\"fill-specializations\""))
        XCTAssertTrue(json.contains("\"supported-platforms\""))
        XCTAssertTrue(json.contains("\"automatic-gradient\""))
        XCTAssertTrue(json.contains("\"appearance\" : \"dark\""))
        // v1 always targets shared square platforms (iPhone/iPad/Mac).
        XCTAssertTrue(json.contains("\"squares\" : \"shared\""))
    }

    func testOmitsUnsetOptionalsFromEncodedDocument() throws {
        let document = IconComposerDocument(
            fill: .solid("srgb:1.00000,1.00000,1.00000,1.00000"),
            groups: [
                IconComposerDocument.Group(layers: [
                    IconComposerDocument.Layer(imageName: "art.png", name: "art"),
                ]),
            ]
        )
        let json = try XCTUnwrap(String(data: document.jsonData(), encoding: .utf8))
        XCTAssertFalse(json.contains("\"glass\""), "unset glass must be omitted (defaults true)")
        XCTAssertFalse(json.contains("\"position\""), "unset position must be omitted (centered)")
        XCTAssertFalse(json.contains("\"hidden\""))
        XCTAssertFalse(json.contains("\"fill-specializations\""))
        XCTAssertFalse(json.contains("\"shadow\""))
        XCTAssertFalse(json.contains("\"translucency\""))
        XCTAssertFalse(json.contains("null"))
    }

    /// Verbatim structure of a real Icon Composer-produced document; decoding
    /// must tolerate every key the app writes, including ones we never emit.
    func testDecodesRealIconComposerDocument() throws {
        let sample = """
        {
          "fill" : {
            "automatic-gradient" : "srgb:0.57919,0.12801,0.57269,1.00000"
          },
          "groups" : [
            {
              "layers" : [
                {
                  "fill-specializations" : [
                    { "value" : { "solid" : "srgb:1.00000,1.00000,1.00000,1.00000" } },
                    { "appearance" : "dark", "value" : { "solid" : "srgb:1.00000,1.00000,1.00000,1.00000" } }
                  ],
                  "glass" : false,
                  "image-name" : "1.circle.png",
                  "name" : "1.circle",
                  "position" : {
                    "scale" : 15,
                    "translation-in-points" : [ 222.40625, 223.2578125 ]
                  }
                }
              ],
              "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
              "translucency" : { "enabled" : true, "value" : 0.5 }
            },
            {
              "layers" : [
                {
                  "image-name" : "LiquidGlassBitMoji.png",
                  "name" : "LiquidGlassBitMoji",
                  "position" : {
                    "scale" : 1.95,
                    "translation-in-points" : [ -20.640625, -126.890625 ]
                  }
                }
              ],
              "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
              "translucency" : { "enabled" : true, "value" : 0.5 }
            }
          ],
          "supported-platforms" : { "squares" : "shared" }
        }
        """

        let document = try JSONDecoder().decode(
            IconComposerDocument.self,
            from: Data(sample.utf8)
        )

        XCTAssertEqual(
            document.fill,
            .automaticGradient("srgb:0.57919,0.12801,0.57269,1.00000")
        )
        XCTAssertEqual(document.groups.count, 2)
        let badge = try XCTUnwrap(document.groups.first?.layers.first)
        XCTAssertEqual(badge.imageName, "1.circle.png")
        XCTAssertEqual(badge.glass, false)
        XCTAssertEqual(badge.position?.scale, 15)
        XCTAssertEqual(badge.position?.translationInPoints, [222.40625, 223.2578125])
        XCTAssertEqual(badge.fillSpecializations?.count, 2)
        XCTAssertEqual(badge.fillSpecializations?[1].appearance, "dark")
        XCTAssertEqual(document.groups[0].shadow, .init(kind: "neutral", opacity: 0.5))
        XCTAssertEqual(document.groups[0].translucency, .init(enabled: true, value: 0.5))
        XCTAssertEqual(document.supportedPlatforms, ["squares": "shared"])
    }

    // MARK: - Color conversion

    func testSrgbStringMatchesIconComposerFormat() throws {
        XCTAssertEqual(
            try IconFill.srgbString(fromHex: "#FFFFFF"),
            "srgb:1.00000,1.00000,1.00000,1.00000"
        )
        XCTAssertEqual(
            try IconFill.srgbString(fromHex: "#00000080"),
            "srgb:0.00000,0.00000,0.00000,0.50196"
        )
    }

    func testSrgbStringRejectsMalformedColor() {
        for bad in ["FFFFFF", "#GGHHII", "#FFF", ""] {
            XCTAssertThrowsError(try IconFill.srgbString(fromHex: bad)) { error in
                guard let smx = error as? SwiftMageXError, case .invalidInput = smx else {
                    return XCTFail("Expected invalidInput for '\(bad)', got \(error)")
                }
            }
        }
    }

    func testIconFillParseAcceptsKnownKindsOnly() throws {
        XCTAssertEqual(try IconFill.parse("solid:#FF0000"), .solid("#FF0000"))
        XCTAssertEqual(try IconFill.parse("auto:#FF0000"), .automaticGradient("#FF0000"))
        XCTAssertEqual(try IconFill.parse("automatic-gradient:#FF0000"), .automaticGradient("#FF0000"))
        XCTAssertThrowsError(try IconFill.parse("#FF0000"))
        XCTAssertThrowsError(try IconFill.parse("linear:#FF0000"))
        XCTAssertThrowsError(try IconFill.parse("solid:red"))
    }

    // MARK: - Builder: grouping and z-order

    func testBuilderEmitsGroupsAndLayersFrontFirst() throws {
        // User order is bottom-to-top; the document lists front-most first.
        let layers = [
            IconLayerSpec(path: "/a/back.png", group: 1),
            IconLayerSpec(path: "/a/mid.png", group: 1),
            IconLayerSpec(path: "/a/front.png", group: 2),
        ]
        let document = try IconPackageBuilder.document(
            layers: layers,
            assetNames: ["back.png", "mid.png", "front.png"],
            fill: .solid("#FFFFFF")
        )

        XCTAssertEqual(document.groups.count, 2)
        XCTAssertEqual(document.groups[0].layers.map(\.name), ["front"])
        XCTAssertEqual(document.groups[1].layers.map(\.name), ["mid", "back"])
    }

    func testBuilderRejectsNonContiguousGroups() {
        let layers = [
            IconLayerSpec(path: "a.png", group: 1),
            IconLayerSpec(path: "b.png", group: 2),
            IconLayerSpec(path: "c.png", group: 1),
        ]
        XCTAssertThrowsError(try IconPackageBuilder.document(
            layers: layers,
            assetNames: ["a.png", "b.png", "c.png"],
            fill: .solid("#FFFFFF")
        )) { error in
            guard let smx = error as? SwiftMageXError, case .invalidInput = smx else {
                return XCTFail("Expected invalidInput, got \(error)")
            }
        }
    }

    func testBuilderRejectsMoreThanFourLayersPerGroup() {
        let layers = (1...5).map { IconLayerSpec(path: "l\($0).png") }
        XCTAssertThrowsError(try IconPackageBuilder.document(
            layers: layers,
            assetNames: layers.map { "\($0.path)" },
            fill: .solid("#FFFFFF")
        ))
    }

    func testBuilderRejectsNonPositiveScaleAndGroup() {
        XCTAssertThrowsError(try IconPackageBuilder.document(
            layers: [IconLayerSpec(path: "a.png", scale: 0)],
            assetNames: ["a.png"],
            fill: .solid("#FFFFFF")
        ))
        XCTAssertThrowsError(try IconPackageBuilder.document(
            layers: [IconLayerSpec(path: "a.png", group: 0)],
            assetNames: ["a.png"],
            fill: .solid("#FFFFFF")
        ))
    }

    // MARK: - Builder: position and per-layer options

    func testBuilderEmitsTranslationAsCenterOffsetVerbatim() throws {
        let document = try IconPackageBuilder.document(
            layers: [
                IconLayerSpec(path: "badge.png", scale: 15, dx: 222.5, dy: 223.25),
                IconLayerSpec(path: "art.png", dy: -126),
                IconLayerSpec(path: "plain.png"),
            ],
            assetNames: ["badge.png", "art.png", "plain.png"],
            fill: .solid("#FFFFFF")
        )

        // Single group, front-first: plain, art, badge.
        let layers = try XCTUnwrap(document.groups.first?.layers)
        XCTAssertNil(layers[0].position, "untouched layer stays centered with no position key")
        XCTAssertEqual(layers[1].position?.scale, 1, "scale defaults to 1 when only dx/dy set")
        XCTAssertEqual(layers[1].position?.translationInPoints, [0, -126])
        XCTAssertEqual(layers[2].position?.scale, 15)
        XCTAssertEqual(layers[2].position?.translationInPoints, [222.5, 223.25])
    }

    func testBuilderMapsGlassAndFill() throws {
        let document = try IconPackageBuilder.document(
            layers: [IconLayerSpec(path: "badge.png", glass: false, fill: "#FF0000")],
            assetNames: ["badge.png"],
            fill: .solid("#FFFFFF")
        )
        let layer = try XCTUnwrap(document.groups.first?.layers.first)
        XCTAssertEqual(layer.glass, false)
        XCTAssertEqual(
            layer.fillSpecializations,
            [.init(value: .solid("srgb:1.00000,0.00000,0.00000,1.00000"))]
        )
    }

    // MARK: - Builder: asset naming

    func testBuilderDeduplicatesAssetNames() throws {
        let plans = try IconPackageBuilder.assetPlans(for: [
            IconLayerSpec(path: "/a/icon.png"),
            IconLayerSpec(path: "/b/icon.png"),
            IconLayerSpec(path: "/c/Icon.jpeg"),
        ])
        XCTAssertEqual(plans.map(\.assetName), ["icon.png", "icon-2.png", "Icon-3.png"])
    }

    func testBuilderSanitizesLayerNames() {
        XCTAssertEqual(
            IconPackageBuilder.layerName(for: IconLayerSpec(path: "/x/My Layer (1).png")),
            "My-Layer--1"
        )
        XCTAssertEqual(
            IconPackageBuilder.layerName(for: IconLayerSpec(path: "/x/---.png")),
            "layer"
        )
        XCTAssertEqual(
            IconPackageBuilder.layerName(for: IconLayerSpec(path: "art.png", name: "Front Glow")),
            "Front-Glow"
        )
    }
}
