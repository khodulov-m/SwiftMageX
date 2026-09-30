import Foundation

/// Output resolution tier for Gemini image models (`imageConfig.imageSize`).
///
/// The tier fixes the long-ish edge of the output: `1K` at 1:1 is 1024×1024,
/// `2K` doubles it, `4K` quadruples it, `512` halves it. Exact pixels per
/// ratio are Google's tables, not ours. Raw values are the wire spelling —
/// uppercase `K`, and no suffix on `512`. Per-model support lives in
/// ``ImageModelDescriptor/resolutions``.
public enum ImageResolution: String, Sendable, CaseIterable, Codable {
    case r512 = "512"
    case r1K = "1K"
    case r2K = "2K"
    case r4K = "4K"

    /// Parses `1K` / `1k` / `512` / `512px`, case-insensitively.
    public init?(parsing raw: String) {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.hasSuffix("PX") { normalized.removeLast(2) }
        self.init(rawValue: normalized)
    }
}
