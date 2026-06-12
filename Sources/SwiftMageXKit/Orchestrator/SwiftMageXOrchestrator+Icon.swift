import Foundation

/// What ``SwiftMageXOrchestrator/composeIcon(layers:fill:output:overwrite:flatPreview:flatPreviewOutput:validate:validator:engine:timestamp:currentDirectoryPath:)``
/// returns. The package path is absolute, like every orchestrator output.
public struct ComposedIconPackage: Sendable, Equatable {
    /// Absolute path of the written `.icon` package directory.
    public let packagePath: URL
    public let layerCount: Int
    public let groupCount: Int
    /// The flat preview PNG, when one was requested.
    public let flatPreview: WrittenImage?
    /// The actool report, when validation was requested (always `passed` —
    /// a failed compile throws instead).
    public let validation: IconValidationReport?

    public init(
        packagePath: URL,
        layerCount: Int,
        groupCount: Int,
        flatPreview: WrittenImage? = nil,
        validation: IconValidationReport? = nil
    ) {
        self.packagePath = packagePath
        self.layerCount = layerCount
        self.groupCount = groupCount
        self.flatPreview = flatPreview
        self.validation = validation
    }
}

extension SwiftMageXOrchestrator {
    /// Assemble an Icon Composer `.icon` package from prepared layer images.
    ///
    /// Purely local — no provider, no API key. Layers are listed bottom-to-top
    /// and copied into the package's `Assets/` folder (PNG verbatim, other
    /// formats re-encoded). The package is staged in a temporary directory
    /// and moved into place, so a half-written package is never observable.
    ///
    /// - Parameters:
    ///   - output: Destination path; `.icon` is appended when missing.
    ///     Defaults to `AppIcon.icon` in the current directory.
    ///   - flatPreview: Also write a flat PNG composite (no Liquid Glass,
    ///     no squircle mask) for READMEs and non-Xcode consumers.
    ///   - validate: Compile-check the finished package (requires Xcode 26).
    /// - Throws: ``SwiftMageXError/io(_:)`` for missing inputs,
    ///   ``SwiftMageXError/invalidInput(_:)`` for spec violations or an
    ///   existing output without `overwrite`, and
    ///   ``SwiftMageXError/configuration(_:)`` when validation is requested
    ///   but actool is unavailable.
    public static func composeIcon(
        layers: [IconLayerSpec],
        fill: IconFill = .solid("#FFFFFF"),
        output: String?,
        overwrite: Bool = false,
        flatPreview: Bool = false,
        flatPreviewOutput: String? = nil,
        validate: Bool = false,
        validator: any IconValidating = ActoolIconValidator(),
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) throws -> ComposedIconPackage {
        let cwd = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        let fileManager = FileManager.default

        // Validate specs and assign asset names before touching the disk.
        let plans = try IconPackageBuilder.assetPlans(for: layers)
        let document = try IconPackageBuilder.document(
            layers: layers,
            assetNames: plans.map(\.assetName),
            fill: fill
        )

        let packageURL = resolvePackageURL(output: output, cwd: cwd)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory) {
            guard overwrite else {
                throw SwiftMageXError.invalidInput(
                    "output already exists: \(packageURL.path); pass overwrite to replace it"
                )
            }
            guard isDirectory.boolValue else {
                throw SwiftMageXError.invalidInput(
                    "output exists and is not an .icon package directory: \(packageURL.path)"
                )
            }
        }

        // Stage the package next to nothing the caller can see, then move.
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("swiftmagex-\(UUID().uuidString).icon", isDirectory: true)
        let assetsDir = staging.appendingPathComponent("Assets", isDirectory: true)
        try wrapIO("could not create staging directory") {
            try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        }
        defer { try? fileManager.removeItem(at: staging) }

        // Load every layer once: validates decodability, yields the pixel
        // size the preview needs, and drives the PNG re-encode decision.
        var loaded: [RasterImage] = []
        for plan in plans {
            let sourceURL = URL(fileURLWithPath: plan.sourcePath, relativeTo: cwd)
                .standardizedFileURL
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw SwiftMageXError.io("layer file not found: \(sourceURL.path)")
            }
            let image = try engine.load(from: sourceURL)
            loaded.append(image)

            let destination = assetsDir.appendingPathComponent(plan.assetName)
            if ImageFormat.detect(at: sourceURL) == .png {
                try wrapIO("could not copy layer \(sourceURL.path)") {
                    try fileManager.copyItem(at: sourceURL, to: destination)
                }
            } else {
                try engine.write(image, to: destination, format: .png, quality: 1.0, metadata: nil)
            }
        }

        let json = try document.jsonData()
        try wrapIO("could not write icon.json") {
            try json.write(to: staging.appendingPathComponent("icon.json"))
        }

        try wrapIO("could not write package to \(packageURL.path)") {
            try fileManager.createDirectory(
                at: packageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: packageURL.path) {
                _ = try fileManager.replaceItemAt(packageURL, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: packageURL)
            }
        }

        var preview: WrittenImage?
        if flatPreview {
            preview = try renderFlatPreview(
                layers: layers,
                images: loaded,
                fill: fill,
                packageURL: packageURL,
                output: flatPreviewOutput,
                engine: engine,
                cwd: cwd
            )
        }

        var report: IconValidationReport?
        if validate {
            let result = try validator.validate(packageAt: packageURL)
            guard result.passed else {
                throw SwiftMageXError.invalidInput(
                    "actool reported errors for \(packageURL.path):\n\(result.output)"
                )
            }
            report = result
        }

        return ComposedIconPackage(
            packagePath: packageURL,
            layerCount: layers.count,
            groupCount: document.groups.count,
            flatPreview: preview,
            validation: report
        )
    }

    // MARK: - Icon internals

    private static func resolvePackageURL(output: String?, cwd: URL) -> URL {
        let raw = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = (raw?.isEmpty ?? true) ? "AppIcon.icon" : raw!
        var url = URL(fileURLWithPath: target, relativeTo: cwd).standardizedFileURL
        if url.pathExtension.lowercased() != "icon" {
            url = url.appendingPathExtension("icon")
        }
        return url
    }

    /// Composites the layers over the fill canvas at 1-pixel-per-point scale.
    private static func renderFlatPreview(
        layers: [IconLayerSpec],
        images: [RasterImage],
        fill: IconFill,
        packageURL: URL,
        output: String?,
        engine: any RasterEngine,
        cwd: URL
    ) throws -> WrittenImage {
        let side = IconPackageBuilder.canvasPoints
        var canvas = try IconFlatPreviewRenderer.canvas(fill: fill, sizePx: side)

        for (spec, image) in zip(layers, images) {
            let layerScale = spec.scale ?? 1
            // CompositeSpec contain-fits the foreground into `scale ×
            // background`; recover "natural size × layerScale" from that:
            // box = 1024·spec.scale / max(w,h) must equal layerScale.
            let longestSide = max(image.width, image.height)
            let placement = CompositeSpec(
                position: .center,
                scale: layerScale * Double(longestSide) / Double(side),
                offsetX: Int((spec.dx ?? 0).rounded()),
                offsetY: Int((spec.dy ?? 0).rounded())
            )
            canvas = try engine.composite(image, onto: canvas, placement)
        }

        let url: URL
        if let raw = output?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            url = URL(fileURLWithPath: raw, relativeTo: cwd).standardizedFileURL
        } else {
            let stem = packageURL.deletingPathExtension().lastPathComponent
            url = packageURL.deletingLastPathComponent()
                .appendingPathComponent("\(stem)-flat.png")
        }
        try engine.write(canvas, to: url, format: .png, quality: 1.0, metadata: nil)
        return WrittenImage(path: url, format: .png, width: canvas.width, height: canvas.height)
    }

    private static func wrapIO(_ message: String, _ body: () throws -> Void) throws {
        do {
            try body()
        } catch let error as SwiftMageXError {
            throw error
        } catch {
            throw SwiftMageXError.io("\(message): \(error.localizedDescription)")
        }
    }
}
