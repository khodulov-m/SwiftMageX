import Foundation

/// The structured JSON shape every CLI command emits under `--json`
/// (spec §12). Lives in the kit so it can be tested without booting the
/// `swiftmagex` executable.
///
/// Encoding is locked to `JSONEncoder(.sortedKeys, .prettyPrinted)` so the
/// output is stable across runs — agents diffing two invocations should see
/// no spurious key reorderings. Nil fields are omitted from the JSON object
/// (custom `encode(to:)`) so the surface matches the documented schema
/// rather than scattering `null` placeholders.
public struct JSONResultEnvelope: Encodable, Equatable, Sendable {
    /// Top-level result discriminator.
    public enum Status: String, Encodable, Sendable {
        case ok
        case error
    }

    /// One written output file.
    public struct Output: Encodable, Equatable, Sendable {
        public let path: String
        public let format: String
        public let width: Int?
        public let height: Int?

        public init(path: String, format: ImageFormat, width: Int?, height: Int?) {
            self.path = path
            self.format = format.rawValue
            self.width = width
            self.height = height
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(path, forKey: .path)
            try c.encode(format, forKey: .format)
            try c.encodeIfPresent(width, forKey: .width)
            try c.encodeIfPresent(height, forKey: .height)
        }

        private enum CodingKeys: String, CodingKey {
            case path, format, width, height
        }
    }

    /// Error envelope; present only when `status == .error`.
    public struct ErrorInfo: Encodable, Equatable, Sendable {
        public let code: Int32
        public let category: String
        public let message: String

        public init(_ error: SwiftMageXError) {
            self.code = error.exitCode
            self.category = error.category
            self.message = error.message
        }
    }

    public let status: Status
    public let command: String
    public let outputs: [Output]?
    public let provider: String?
    public let model: String?
    public let error: ErrorInfo?

    private init(
        status: Status,
        command: String,
        outputs: [Output]?,
        provider: String?,
        model: String?,
        error: ErrorInfo?
    ) {
        self.status = status
        self.command = command
        self.outputs = outputs
        self.provider = provider
        self.model = model
        self.error = error
    }

    public static func success(
        command: String,
        outputs: [Output],
        provider: String? = nil,
        model: String? = nil
    ) -> JSONResultEnvelope {
        .init(
            status: .ok,
            command: command,
            outputs: outputs,
            provider: provider,
            model: model,
            error: nil
        )
    }

    public static func failure(
        command: String,
        error: SwiftMageXError
    ) -> JSONResultEnvelope {
        .init(
            status: .error,
            command: command,
            outputs: nil,
            provider: nil,
            model: nil,
            error: ErrorInfo(error)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status, forKey: .status)
        try c.encode(command, forKey: .command)
        try c.encodeIfPresent(outputs, forKey: .outputs)
        try c.encodeIfPresent(provider, forKey: .provider)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(error, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case status, command, outputs, provider, model, error
    }

    /// Encode this envelope to a deterministic, pretty-printed JSON blob.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }
}
