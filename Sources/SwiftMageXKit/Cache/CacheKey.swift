import CryptoKit
import Foundation

/// Content-addressed key for a ``GenerationRequest``.
///
/// Computed as `sha256(canonical_json(request_fields))` and rendered as a
/// lowercase hex string. The payload includes every input that materially
/// affects the response — model, prompt, size, count, seed, and the SHA-256
/// of every reference image and mask byte payload (so identical bytes hit
/// the cache regardless of source path or filename).
public enum CacheKey {
    /// Compute the cache key for `request`. Pure — no I/O — so callers can
    /// invoke it eagerly inside the orchestrator without paying for a network
    /// or disk hit on every call.
    public static func compute(from request: GenerationRequest) -> String {
        let payload = Payload(
            model: request.model,
            prompt: request.prompt,
            size: request.size.rawValue,
            count: request.count,
            seed: request.seed,
            refs: request.referenceImages.map { hexSHA256($0.data) },
            mask: request.mask.map { hexSHA256($0) },
            maskMimeType: request.maskMimeType
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Deterministic encoding is required for the hash to be stable across
        // runs; .sortedKeys gives us that without any extra serialization
        // dance because every field in `Payload` is a primitive or array.
        let data = (try? encoder.encode(payload)) ?? Data()
        return hexSHA256(data)
    }

    // MARK: - Internals

    /// The canonical pre-hash payload. Field names and ordering are part of
    /// the wire format — renaming or reordering invalidates every cached
    /// entry on disk. `refs` / `mask` / `maskMimeType` are omitted from the
    /// encoded JSON when empty / nil so a text-to-image request hashes the
    /// same regardless of whether the edit fields are even present.
    private struct Payload: Encodable {
        let model: String
        let prompt: String
        let size: String
        let count: Int
        let seed: UInt64?
        let refs: [String]
        let mask: String?
        let maskMimeType: String?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(model, forKey: .model)
            try c.encode(prompt, forKey: .prompt)
            try c.encode(size, forKey: .size)
            try c.encode(count, forKey: .count)
            try c.encodeIfPresent(seed, forKey: .seed)
            if !refs.isEmpty {
                try c.encode(refs, forKey: .refs)
            }
            try c.encodeIfPresent(mask, forKey: .mask)
            try c.encodeIfPresent(maskMimeType, forKey: .maskMimeType)
        }

        enum CodingKeys: String, CodingKey {
            case model, prompt, size, count, seed, refs, mask, maskMimeType
        }
    }

    private static func hexSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
