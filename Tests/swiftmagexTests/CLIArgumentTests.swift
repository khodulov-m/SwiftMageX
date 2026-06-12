import ArgumentParser
import XCTest
@testable import swiftmagex

/// Exercises the CLI's ArgumentParser surface — parsing + `validate()` — for
/// each subcommand. The body of `run()` is the orchestrator's responsibility
/// and is tested in `SwiftMageXKitTests` and `swiftmagexMCPTests`; here we
/// guard the user-facing surface (flag shapes, required arguments, mutually
/// exclusive combinations) so a future refactor of the CLI can't silently
/// loosen what the help text promises.
final class CLIArgumentTests: XCTestCase {
    // MARK: - generate

    func testGenerateRequiresPrompt() {
        XCTAssertThrowsError(try GenerateCommand.parse([]))
    }

    func testGenerateRejectsEmptyPrompt() {
        XCTAssertThrowsError(try GenerateCommand.parse(["   "])) { error in
            XCTAssertTrue(
                String(describing: error).contains("Prompt"),
                "expected prompt-related validation error, got: \(error)"
            )
        }
    }

    func testGenerateRejectsCountOutOfRange() {
        XCTAssertThrowsError(try GenerateCommand.parse(["a prompt", "--count", "0"]))
        XCTAssertThrowsError(try GenerateCommand.parse(["a prompt", "--count", "5"]))
    }

    func testGenerateAcceptsValidCount() throws {
        let cmd = try GenerateCommand.parse(["a prompt", "--count", "4", "--seed", "42"])
        XCTAssertEqual(cmd.prompt, "a prompt")
        XCTAssertEqual(cmd.count, 4)
        XCTAssertEqual(cmd.seed, 42)
    }

    func testGenerateSizeFlagAcceptsAllVariants() throws {
        for variant in ["square", "portrait", "landscape"] {
            XCTAssertNoThrow(try GenerateCommand.parse(["p", "--size", variant]))
        }
        XCTAssertThrowsError(try GenerateCommand.parse(["p", "--size", "panorama"]))
    }

    // MARK: - resize

    func testResizeRequiresAtLeastOneDimension() {
        XCTAssertThrowsError(try ResizeCommand.parse(["in.png"])) { error in
            XCTAssertTrue(
                String(describing: error).contains("width") ||
                    String(describing: error).contains("height"),
                "expected dim-required error, got: \(error)"
            )
        }
    }

    func testResizeRejectsCoverWithoutBothDimensions() {
        XCTAssertThrowsError(
            try ResizeCommand.parse(["in.png", "--width", "100", "--fit", "cover"])
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("cover"),
                "expected fit-cover validation error, got: \(error)"
            )
        }
    }

    func testResizeRejectsFillWithoutBothDimensions() {
        XCTAssertThrowsError(
            try ResizeCommand.parse(["in.png", "--height", "100", "--fit", "fill"])
        )
    }

    func testResizeRejectsQualityOutOfRange() {
        XCTAssertThrowsError(
            try ResizeCommand.parse(["in.png", "--width", "10", "--quality", "1.5"])
        )
        XCTAssertThrowsError(
            try ResizeCommand.parse(["in.png", "--width", "10", "--quality", "-0.1"])
        )
    }

    func testResizeAcceptsSingleDimensionContain() throws {
        let cmd = try ResizeCommand.parse(["in.png", "--width", "256"])
        XCTAssertEqual(cmd.input, "in.png")
        XCTAssertEqual(cmd.width, 256)
        XCTAssertNil(cmd.height)
        XCTAssertEqual(cmd.fit, .contain)
    }

    func testResizeFormatFlagAcceptsAliases() throws {
        // `jpg` is an accepted alias for `jpeg` per the CLI parser.
        let cmd = try ResizeCommand.parse(["in.png", "--width", "10", "--format", "jpg"])
        XCTAssertEqual(cmd.format, .jpeg)
    }

    // MARK: - text

    func testTextRequiresInputAndText() {
        XCTAssertThrowsError(try TextCommand.parse([]))
        XCTAssertThrowsError(try TextCommand.parse(["in.png"]))
    }

    func testTextRejectsEmptyText() {
        XCTAssertThrowsError(try TextCommand.parse(["in.png", "--text", "   "])) { error in
            XCTAssertTrue(
                String(describing: error).contains("text"),
                "expected empty-text error, got: \(error)"
            )
        }
    }

    func testTextRejectsNonPositiveFontSize() {
        XCTAssertThrowsError(
            try TextCommand.parse(["in.png", "--text", "hi", "--font-size", "0"])
        )
    }

    func testTextRejectsNegativeStrokeWidth() {
        XCTAssertThrowsError(
            try TextCommand.parse(["in.png", "--text", "hi", "--stroke-width", "-1"])
        )
    }

    func testTextAcceptsAllPositions() throws {
        for raw in [
            "top", "center", "bottom",
            "top-left", "top-right", "bottom-left", "bottom-right",
        ] {
            XCTAssertNoThrow(
                try TextCommand.parse(["in.png", "--text", "x", "--position", raw]),
                "expected position '\(raw)' to parse"
            )
        }
    }

    // MARK: - composite

    func testCompositeRequiresInputAndOverlay() {
        XCTAssertThrowsError(try CompositeCommand.parse([]))
        XCTAssertThrowsError(try CompositeCommand.parse(["bg.png"]))
    }

    func testCompositeAcceptsValidArguments() throws {
        let cmd = try CompositeCommand.parse([
            "bg.png", "--overlay", "fg.png", "--scale", "0.5", "--position", "bottom-right",
        ])
        XCTAssertEqual(cmd.input, "bg.png")
        XCTAssertEqual(cmd.overlay, "fg.png")
        XCTAssertEqual(cmd.scale, 0.5)
        XCTAssertEqual(cmd.position, .bottomRight)
    }

    func testCompositeRejectsNonPositiveScale() {
        XCTAssertThrowsError(try CompositeCommand.parse(["bg.png", "--overlay", "fg.png", "--scale", "0"]))
    }

    func testCompositeRejectsOpacityOutOfRange() {
        XCTAssertThrowsError(try CompositeCommand.parse(["bg.png", "--overlay", "fg.png", "--opacity", "1.5"]))
    }

    // MARK: - appstore

    func testAppStoreRequiresScreenshotAndBackground() {
        XCTAssertThrowsError(try AppStoreCommand.parse([]))
        XCTAssertThrowsError(try AppStoreCommand.parse(["shot.png"]))
    }

    func testAppStoreAcceptsMultipleDevicesAndAll() throws {
        let cmd = try AppStoreCommand.parse([
            "shot.png", "--background", "bg.png",
            "--device", "iphone-6.9", "--device", "iphone-5.5",
        ])
        XCTAssertEqual(cmd.device, ["iphone-6.9", "iphone-5.5"])
        XCTAssertNoThrow(try AppStoreCommand.parse(["shot.png", "--background", "bg.png", "--device", "all"]))
    }

    func testAppStoreRejectsUnknownDevice() {
        XCTAssertThrowsError(
            try AppStoreCommand.parse(["shot.png", "--background", "bg.png", "--device", "bogus"])
        )
    }

    func testAppStoreParsesScreenRect() throws {
        let cmd = try AppStoreCommand.parse([
            "shot.png", "--background", "bg.png", "--frame", "f.png", "--screen-rect", "10,20,300,640",
        ])
        XCTAssertEqual(cmd.screenRect, "10,20,300,640")
    }

    func testAppStoreRejectsMalformedScreenRect() {
        XCTAssertThrowsError(
            try AppStoreCommand.parse(["shot.png", "--background", "bg.png", "--screen-rect", "10,20,300"])
        )
    }

    func testAppStoreRejectsNonPositiveScale() {
        XCTAssertThrowsError(
            try AppStoreCommand.parse(["shot.png", "--background", "bg.png", "--scale", "0"])
        )
    }

    // MARK: - remove-bg

    func testRemoveBackgroundRequiresInput() {
        XCTAssertThrowsError(try RemoveBackgroundCommand.parse([]))
    }

    func testRemoveBackgroundParsesInputAndOutput() throws {
        let cmd = try RemoveBackgroundCommand.parse(["photo.jpg", "-o", "cutout.png"])
        XCTAssertEqual(cmd.input, "photo.jpg")
        XCTAssertEqual(cmd.output, "cutout.png")
    }

    // MARK: - crop

    func testCropRequiresInputAndAspect() {
        XCTAssertThrowsError(try CropCommand.parse([]))
        XCTAssertThrowsError(try CropCommand.parse(["photo.jpg"]))
    }

    func testCropParsesAspectAndOptionalOutput() throws {
        let cmd = try CropCommand.parse(["photo.jpg", "--aspect", "9:16", "-o", "out.jpg"])
        XCTAssertEqual(cmd.input, "photo.jpg")
        XCTAssertEqual(cmd.aspect, "9:16")
        XCTAssertEqual(cmd.output, "out.jpg")
    }

    func testCropRejectsMalformedAspect() {
        XCTAssertThrowsError(try CropCommand.parse(["photo.jpg", "--aspect", "9-16"]))
        XCTAssertThrowsError(try CropCommand.parse(["photo.jpg", "--aspect", "0:1"]))
        XCTAssertThrowsError(try CropCommand.parse(["photo.jpg", "--aspect", "abc"]))
    }

    // MARK: - icon

    func testIconRequiresAtLeastOneLayer() {
        XCTAssertThrowsError(try IconCommand.parse([]))
    }

    func testIconParsesLayerOptions() throws {
        let spec = try IconCommand.parseLayer(
            "mark.png,name=Front Glow,glass=false,scale=0.8,dx=-20,dy=10,fill=#FF0000,group=2"
        )
        XCTAssertEqual(spec.path, "mark.png")
        XCTAssertEqual(spec.name, "Front Glow")
        XCTAssertEqual(spec.glass, false)
        XCTAssertEqual(spec.scale, 0.8)
        XCTAssertEqual(spec.dx, -20)
        XCTAssertEqual(spec.dy, 10)
        XCTAssertEqual(spec.fill, "#FF0000")
        XCTAssertEqual(spec.group, 2)
    }

    func testIconLayerDefaultsLeaveOptionsUnset() throws {
        let spec = try IconCommand.parseLayer("bg.png")
        XCTAssertEqual(spec.path, "bg.png")
        XCTAssertNil(spec.name)
        XCTAssertNil(spec.glass)
        XCTAssertNil(spec.scale)
        XCTAssertNil(spec.dx)
        XCTAssertNil(spec.dy)
        XCTAssertNil(spec.fill)
        XCTAssertEqual(spec.group, 1)
    }

    func testIconLayerPathMayContainCommas() throws {
        XCTAssertEqual(try IconCommand.parseLayer("my,file.png").path, "my,file.png")
        XCTAssertEqual(
            try IconCommand.parseLayer("my,file.png,glass=false").path,
            "my,file.png"
        )
    }

    func testIconRejectsMalformedLayerOptions() {
        XCTAssertThrowsError(try IconCommand.parseLayer("l.png,scale=abc"))
        XCTAssertThrowsError(try IconCommand.parseLayer("l.png,scale=0"))
        XCTAssertThrowsError(try IconCommand.parseLayer("l.png,glass=2"))
        XCTAssertThrowsError(try IconCommand.parseLayer("l.png,group=0"))
        XCTAssertThrowsError(try IconCommand.parseLayer("l.png,fill=red"))
        XCTAssertThrowsError(try IconCommand.parseLayer("l.png,bogus=1"))
        XCTAssertThrowsError(try IconCommand.parseLayer("l.png,glass="))
    }

    func testIconValidatesFillFlag() throws {
        XCTAssertThrowsError(try IconCommand.parse(["l.png", "--fill", "nope"]))
        XCTAssertThrowsError(try IconCommand.parse(["l.png", "--fill", "solid:red"]))
        let cmd = try IconCommand.parse(["l.png", "--fill", "auto:#7B1FA2"])
        XCTAssertEqual(cmd.fill, "auto:#7B1FA2")
    }

    func testIconFlagDefaults() throws {
        let cmd = try IconCommand.parse(["l.png"])
        XCTAssertEqual(cmd.fill, "solid:#FFFFFF")
        XCTAssertFalse(cmd.overwrite)
        XCTAssertFalse(cmd.flatPreview)
        XCTAssertFalse(cmd.runValidation)
        XCTAssertNil(cmd.output)
    }

    // MARK: - root

    func testRootRegistersAllSubcommands() {
        let names = SwiftMageX.configuration.subcommands.map { $0.configuration.commandName }
        XCTAssertEqual(
            Set(names),
            ["generate", "edit", "resize", "text", "composite", "appstore", "remove-bg", "crop", "icon"]
        )
    }
}
