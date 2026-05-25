import Foundation
import MCP

/// Typed extraction of MCP tool arguments (`[String: Value]`).
///
/// Per-tool handlers turn the raw arguments dictionary into a strongly typed
/// input struct before calling into ``SwiftMageXKit``. Failures here surface as
/// `MCPError.invalidParams`, distinguishing schema-level problems (missing
/// required keys, wrong types) from `SwiftMageXError` thrown by the kit.
///
/// Scope is intentionally narrow — only the conversions the three tools need.
struct ToolArguments {
    let raw: [String: Value]
    let toolName: String

    init(_ raw: [String: Value]?, toolName: String) {
        self.raw = raw ?? [:]
        self.toolName = toolName
    }

    func requiredString(_ key: String) throws -> String {
        guard let value = raw[key] else {
            throw MCPError.invalidParams("\(toolName): missing required argument '\(key)'")
        }
        guard case .string(let s) = value else {
            throw MCPError.invalidParams("\(toolName): '\(key)' must be a string")
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MCPError.invalidParams("\(toolName): '\(key)' must not be empty")
        }
        return s
    }

    func optionalString(_ key: String) throws -> String? {
        guard let value = raw[key] else { return nil }
        if case .null = value { return nil }
        guard case .string(let s) = value else {
            throw MCPError.invalidParams("\(toolName): '\(key)' must be a string")
        }
        return s
    }

    func optionalInt(_ key: String) throws -> Int? {
        guard let value = raw[key] else { return nil }
        if case .null = value { return nil }
        // Accept 42 and 42.0 alike — agents serializing JSON sometimes pass
        // integers as doubles. Strings are still rejected.
        guard let i = Int(value, strict: false) else {
            throw MCPError.invalidParams("\(toolName): '\(key)' must be an integer")
        }
        return i
    }

    func optionalUInt64(_ key: String) throws -> UInt64? {
        guard let value = raw[key] else { return nil }
        if case .null = value { return nil }
        guard let i = Int(value, strict: false), i >= 0 else {
            throw MCPError.invalidParams("\(toolName): '\(key)' must be a non-negative integer")
        }
        return UInt64(i)
    }

    func optionalDouble(_ key: String) throws -> Double? {
        guard let value = raw[key] else { return nil }
        if case .null = value { return nil }
        guard let d = Double(value) else {
            throw MCPError.invalidParams("\(toolName): '\(key)' must be a number")
        }
        return d
    }

    /// Decodes an array-of-strings argument. Returns `nil` when absent.
    /// Accepts a JSON array of strings; also tolerates a single string so
    /// agents can pass one value without wrapping it in an array.
    func optionalStringArray(_ key: String) throws -> [String]? {
        guard let value = raw[key] else { return nil }
        if case .null = value { return nil }
        if case .string(let s) = value { return [s] }
        guard case .array(let items) = value else {
            throw MCPError.invalidParams("\(toolName): '\(key)' must be an array of strings")
        }
        return try items.map { item in
            guard case .string(let s) = item else {
                throw MCPError.invalidParams("\(toolName): '\(key)' must contain only strings")
            }
            return s
        }
    }

    /// Decodes an enum-shaped string argument.
    func optionalEnum<T: RawRepresentable>(
        _ key: String,
        as type: T.Type
    ) throws -> T? where T.RawValue == String {
        guard let raw = try optionalString(key) else { return nil }
        guard let value = T(rawValue: raw.lowercased()) else {
            throw MCPError.invalidParams("\(toolName): '\(key)' has unrecognized value '\(raw)'")
        }
        return value
    }
}
