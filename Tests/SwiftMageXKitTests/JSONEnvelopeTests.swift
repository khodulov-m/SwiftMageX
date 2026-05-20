import Foundation
import XCTest
@testable import SwiftMageXKit

final class JSONEnvelopeTests: XCTestCase {
    // MARK: - Error envelope

    func testErrorJSONEnvelopeForProviderFailure() async throws {
        let provider = MockImageProvider(
            capabilities: .init(
                supportsSeed: false,
                maxBatchSize: 4,
                supportedSizes: ImageSize.allCases
            ),
            throwing: .provider("quota exhausted after 5 retries")
        )
        let request = GenerationRequest(
            prompt: "anything",
            size: .square,
            count: 1,
            seed: nil,
            model: "gemini-2.5-flash-image"
        )

        do {
            _ = try await SwiftMageXOrchestrator.generate(
                request: request,
                output: nil,
                provider: provider
            )
            XCTFail("Expected provider failure to throw")
        } catch let error as SwiftMageXError {
            let envelope = JSONResultEnvelope.failure(command: "generate", error: error)
            let data = try envelope.jsonData()
            let parsed = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: data) as? [String: Any]
            )

            XCTAssertEqual(parsed["status"] as? String, "error")
            XCTAssertEqual(parsed["command"] as? String, "generate")
            XCTAssertNil(parsed["outputs"], "outputs key must be omitted on error")
            XCTAssertNil(parsed["provider"], "provider key must be omitted on error")
            XCTAssertNil(parsed["model"], "model key must be omitted on error")

            let errObj = try XCTUnwrap(parsed["error"] as? [String: Any])
            XCTAssertEqual(errObj["code"] as? Int, 3)
            XCTAssertEqual(errObj["category"] as? String, "provider")
            XCTAssertEqual(errObj["message"] as? String, "quota exhausted after 5 retries")
        }
    }

    // MARK: - Success envelope

    func testSuccessJSONEnvelopeContainsAllOutputFields() throws {
        let envelope = JSONResultEnvelope.success(
            command: "generate",
            outputs: [
                .init(path: "/tmp/out_1.png", format: .png, width: 1024, height: 1024),
                .init(path: "/tmp/out_2.png", format: .png, width: 1024, height: 1024)
            ],
            provider: "gemini",
            model: "gemini-2.5-flash-image"
        )
        let data = try envelope.jsonData()
        let parsed = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(parsed["status"] as? String, "ok")
        XCTAssertEqual(parsed["command"] as? String, "generate")
        XCTAssertEqual(parsed["provider"] as? String, "gemini")
        XCTAssertEqual(parsed["model"] as? String, "gemini-2.5-flash-image")
        XCTAssertNil(parsed["error"], "error key must be omitted on success")

        let outputs = try XCTUnwrap(parsed["outputs"] as? [[String: Any]])
        XCTAssertEqual(outputs.count, 2)
        let first = try XCTUnwrap(outputs.first)
        XCTAssertEqual(first["path"] as? String, "/tmp/out_1.png")
        XCTAssertEqual(first["format"] as? String, "png")
        XCTAssertEqual(first["width"] as? Int, 1024)
        XCTAssertEqual(first["height"] as? Int, 1024)
    }

    func testSuccessJSONEnvelopeOmitsProviderAndModelForLocalCommands() throws {
        let envelope = JSONResultEnvelope.success(
            command: "resize",
            outputs: [.init(path: "/tmp/out.png", format: .png, width: 256, height: 256)]
        )
        let data = try envelope.jsonData()
        let parsed = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(parsed["status"] as? String, "ok")
        XCTAssertEqual(parsed["command"] as? String, "resize")
        XCTAssertNil(parsed["provider"])
        XCTAssertNil(parsed["model"])
        XCTAssertNil(parsed["error"])
    }

    // MARK: - Determinism

    func testJSONEnvelopeUsesSortedKeys() throws {
        let envelope = JSONResultEnvelope.success(
            command: "generate",
            outputs: [.init(path: "/tmp/a.png", format: .png, width: 1, height: 1)],
            provider: "gemini",
            model: "gemini-2.5-flash-image"
        )
        let data = try envelope.jsonData()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        // .sortedKeys: alphabetical at every level.
        let keyOrder = ["command", "model", "outputs", "provider", "status"]
        var lastRange = text.startIndex..<text.startIndex
        for key in keyOrder {
            guard let range = text.range(of: "\"\(key)\"", range: lastRange.upperBound..<text.endIndex) else {
                return XCTFail("Key \(key) missing or out of order in:\n\(text)")
            }
            lastRange = range
        }
    }

    // MARK: - Exit codes

    func testExitCodeForEachErrorCategory() {
        let cases: [(SwiftMageXError, Int32, String)] = [
            (.invalidInput("x"), 2, "invalid_input"),
            (.provider("x"), 3, "provider"),
            (.configuration("x"), 4, "configuration"),
            (.raster("x"), 1, "raster"),
            (.io("x"), 1, "io")
        ]
        for (error, expectedCode, expectedCategory) in cases {
            XCTAssertEqual(
                error.exitCode,
                expectedCode,
                "exitCode for \(error) should be \(expectedCode)"
            )
            XCTAssertEqual(
                error.category,
                expectedCategory,
                "category for \(error) should be \(expectedCategory)"
            )
        }
    }

    func testErrorEnvelopeCarriesCorrectExitCodePerCategory() throws {
        for error in [
            SwiftMageXError.invalidInput("x"),
            .provider("x"),
            .configuration("x"),
            .raster("x"),
            .io("x")
        ] {
            let envelope = JSONResultEnvelope.failure(command: "generate", error: error)
            let data = try envelope.jsonData()
            let parsed = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            let err = try XCTUnwrap(parsed["error"] as? [String: Any])
            XCTAssertEqual(err["code"] as? Int, Int(error.exitCode))
            XCTAssertEqual(err["category"] as? String, error.category)
        }
    }
}
