import Foundation

/// Pure assembly of an `icon.json` document and the asset-copy plan from
/// user layer specs. No disk I/O — fully unit-testable; the orchestrator
/// owns staging, copying, and writing.
enum IconPackageBuilder {
    /// Icon Composer canvas side, in points.
    static let canvasPoints = 1024
    /// Icon Composer caps a group at four layers.
    static let maxLayersPerGroup = 4

    /// Where one source image lands inside the package's `Assets/` folder.
    struct AssetPlan: Equatable {
        let sourcePath: String
        /// Destination file name (always `.png` — non-PNG sources are
        /// re-encoded on copy).
        let assetName: String
    }

    /// Assigns a unique `Assets/` file name to every layer, derived from the
    /// layer name and deduplicated case-insensitively with `-2`, `-3`, …
    static func assetPlans(for layers: [IconLayerSpec]) throws -> [AssetPlan] {
        guard !layers.isEmpty else {
            throw SwiftMageXError.invalidInput("at least one layer is required")
        }
        var used: Set<String> = []
        return layers.map { spec in
            let stem = layerName(for: spec)
            var candidate = stem
            var suffix = 2
            while used.contains(candidate.lowercased()) {
                candidate = "\(stem)-\(suffix)"
                suffix += 1
            }
            used.insert(candidate.lowercased())
            return AssetPlan(sourcePath: spec.path, assetName: "\(candidate).png")
        }
    }

    /// The layer's display name: explicit `name` if given, else the source
    /// file stem; sanitized either way so it is safe as an asset file name.
    static func layerName(for spec: IconLayerSpec) -> String {
        let raw = spec.name
            ?? URL(fileURLWithPath: spec.path).deletingPathExtension().lastPathComponent
        let sanitized = raw.map { char -> Character in
            char.isLetter || char.isNumber || char == "-" || char == "_" || char == "."
                ? char
                : "-"
        }
        let result = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return result.isEmpty ? "layer" : result
    }

    /// Builds the document from validated specs and their asset names
    /// (parallel arrays, both bottom-to-top).
    ///
    /// Grouping: layers carry a 1-based `group` index that must be
    /// non-decreasing bottom-to-top (a group is a contiguous stack); gaps are
    /// fine — distinct values are collapsed in order of appearance. The
    /// document lists groups and the layers inside them front-first, so both
    /// sequences are reversed on emission.
    static func document(
        layers: [IconLayerSpec],
        assetNames: [String],
        fill: IconFill
    ) throws -> IconComposerDocument {
        precondition(layers.count == assetNames.count, "specs and asset names must align")
        guard !layers.isEmpty else {
            throw SwiftMageXError.invalidInput("at least one layer is required")
        }

        // Collapse group indices into contiguous runs, bottom-to-top.
        var runs: [[(spec: IconLayerSpec, assetName: String)]] = []
        var previousGroup: Int?
        for (spec, assetName) in zip(layers, assetNames) {
            guard spec.group >= 1 else {
                throw SwiftMageXError.invalidInput(
                    "layer '\(layerName(for: spec))': group must be >= 1 (got \(spec.group))"
                )
            }
            if let scale = spec.scale, scale <= 0 {
                throw SwiftMageXError.invalidInput(
                    "layer '\(layerName(for: spec))': scale must be positive (got \(scale))"
                )
            }
            if let previous = previousGroup, spec.group < previous {
                throw SwiftMageXError.invalidInput(
                    "layers of a group must be contiguous bottom-to-top; "
                        + "group \(spec.group) appears after group \(previous)"
                )
            }
            if spec.group == previousGroup {
                runs[runs.count - 1].append((spec, assetName))
            } else {
                runs.append([(spec, assetName)])
            }
            previousGroup = spec.group
        }

        for run in runs where run.count > maxLayersPerGroup {
            throw SwiftMageXError.invalidInput(
                "group \(run[0].spec.group) has \(run.count) layers; "
                    + "Icon Composer allows at most \(maxLayersPerGroup) per group"
            )
        }

        var documentGroups: [IconComposerDocument.Group] = []
        for run in runs.reversed() {
            var documentLayers: [IconComposerDocument.Layer] = []
            for (spec, assetName) in run.reversed() {
                documentLayers.append(try documentLayer(spec: spec, assetName: assetName))
            }
            documentGroups.append(IconComposerDocument.Group(layers: documentLayers))
        }

        return IconComposerDocument(
            fill: try fill.documentFill(),
            groups: documentGroups
        )
    }

    private static func documentLayer(
        spec: IconLayerSpec,
        assetName: String
    ) throws -> IconComposerDocument.Layer {
        var position: IconComposerDocument.Position?
        if spec.scale != nil || spec.dx != nil || spec.dy != nil {
            position = IconComposerDocument.Position(
                scale: spec.scale ?? 1,
                translationInPoints: [spec.dx ?? 0, spec.dy ?? 0]
            )
        }

        var fillSpecializations: [IconComposerDocument.FillSpecialization]?
        if let hex = spec.fill {
            fillSpecializations = [
                IconComposerDocument.FillSpecialization(
                    value: .solid(try IconFill.srgbString(fromHex: hex))
                ),
            ]
        }

        return IconComposerDocument.Layer(
            imageName: assetName,
            name: layerName(for: spec),
            glass: spec.glass,
            position: position,
            fillSpecializations: fillSpecializations
        )
    }
}
