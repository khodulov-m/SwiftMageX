import Foundation

/// An exact output aspect ratio (`width:height`) for generation and edit
/// requests.
///
/// The cases are the union Google's `imageConfig.aspectRatio` accepts, verified
/// against a live `:generateContent` 400 on 2026-09-30. Not every model
/// renders every ratio — the extreme strips (`1:4`, `4:1`, `1:8`, `8:1`) are
/// Gemini 3.1 only; ``ImageModelDescriptor/aspectRatios`` holds the per-model
/// set. The server validates only against the union, so the per-model check
/// is ours to make.
public enum AspectRatio: String, Sendable, CaseIterable, Codable {
    case r1x1 = "1:1"
    case r1x4 = "1:4"
    case r1x8 = "1:8"
    case r2x3 = "2:3"
    case r3x2 = "3:2"
    case r3x4 = "3:4"
    case r4x1 = "4:1"
    case r4x3 = "4:3"
    case r4x5 = "4:5"
    case r5x4 = "5:4"
    case r8x1 = "8:1"
    case r9x16 = "9:16"
    case r16x9 = "16:9"
    case r21x9 = "21:9"

    /// The ten ratios every current Gemini image model supports.
    public static let classic: [AspectRatio] = [
        .r1x1, .r2x3, .r3x2, .r3x4, .r4x3, .r4x5, .r5x4, .r9x16, .r16x9, .r21x9,
    ]

    /// Parses `16:9`, tolerating surrounding whitespace and `x` / `/` as the
    /// separator (`16x9`, `16/9`) since shells and agents write it either way.
    public init?(parsing raw: String) {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "x", with: ":")
            .replacingOccurrences(of: "/", with: ":")
        self.init(rawValue: normalized)
    }
}

extension ImageSize {
    /// The exact ratio each coarse preset stands for.
    public var aspectRatio: AspectRatio {
        switch self {
        case .square: return .r1x1
        case .portrait: return .r9x16
        case .landscape: return .r16x9
        }
    }
}
