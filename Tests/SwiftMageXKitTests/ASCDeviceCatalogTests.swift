import XCTest
@testable import SwiftMageXKit

final class ASCDeviceCatalogTests: XCTestCase {
    func testEmptyListResolvesToDefault() throws {
        let sizes = try ASCDeviceCatalog.sizes(for: [])
        XCTAssertEqual(sizes.map(\.id), ["iphone-6.9"])
        XCTAssertEqual(sizes[0].width, 1290)
        XCTAssertEqual(sizes[0].height, 2796)
    }

    func testAllKeywordExpandsToEveryDevice() throws {
        let sizes = try ASCDeviceCatalog.sizes(for: ["all"])
        XCTAssertEqual(sizes.map(\.id), ASCDeviceCatalog.all.map(\.id))
        XCTAssertEqual(sizes.count, 3)
    }

    func testDuplicatesAreDeduplicatedInOrder() throws {
        let sizes = try ASCDeviceCatalog.sizes(for: ["iphone-6.9", "iphone-6.9", "iphone-5.5"])
        XCTAssertEqual(sizes.map(\.id), ["iphone-6.9", "iphone-5.5"])
    }

    func testUnknownDeviceThrowsInvalidInput() {
        XCTAssertThrowsError(try ASCDeviceCatalog.sizes(for: ["iphone-99"])) { error in
            guard let smx = error as? SwiftMageXError, case .invalidInput = smx else {
                return XCTFail("Expected SwiftMageXError.invalidInput, got \(error)")
            }
        }
    }

    func testLandscapeSwapsDimensions() {
        let size = ASCDeviceSize(id: "x", label: "x", width: 1242, height: 2208)
        XCTAssertEqual(size.dimensions(for: .portrait).width, 1242)
        XCTAssertEqual(size.dimensions(for: .portrait).height, 2208)
        XCTAssertEqual(size.dimensions(for: .landscape).width, 2208)
        XCTAssertEqual(size.dimensions(for: .landscape).height, 1242)
    }
}
