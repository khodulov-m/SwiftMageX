import Foundation

/// Environment-driven configuration for SwiftMageX (spec §10).
///
/// MVP 0.1 has no config file and no Keychain integration; everything comes
/// from process environment variables and CLI flags. The frontends call into
/// ``Configuration`` so the two share identical lookup behavior.
public enum Configuration {
    /// Names of the environment variables consulted at runtime.
    public enum EnvironmentKey {
        /// The preferred name for the Gemini API key.
        public static let primaryAPIKey = "SWIFTMAGEX_GEMINI_API_KEY"
        /// Fallback API key name, honored when the primary is unset.
        public static let fallbackAPIKey = "GEMINI_API_KEY"
        /// Default output directory for generated files.
        public static let outputDirectory = "SWIFTMAGEX_OUTPUT_DIR"
    }

    /// Resolves the Gemini API key from the process environment.
    ///
    /// Looks up ``EnvironmentKey/primaryAPIKey`` first, falling back to
    /// ``EnvironmentKey/fallbackAPIKey``. Returns `nil` if neither is set or
    /// both are empty after trimming.
    ///
    /// - Parameter environment: The environment to inspect. Defaults to the
    ///   current process environment; injectable for tests.
    public static func resolvedAPIKey(
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let key = environment[EnvironmentKey.primaryAPIKey], !key.trimmingCharacters(in: .whitespaces).isEmpty {
            return key
        }
        if let key = environment[EnvironmentKey.fallbackAPIKey], !key.trimmingCharacters(in: .whitespaces).isEmpty {
            return key
        }
        return nil
    }

    /// Resolves the effective `--output` target for the generation commands
    /// (`generate` / `edit` / `appstore`) per spec §10 / §12.
    ///
    /// Precedence: an explicit `--output` always wins; otherwise the
    /// ``EnvironmentKey/outputDirectory`` (`SWIFTMAGEX_OUTPUT_DIR`) is used
    /// when set; otherwise `nil`, letting the caller fall back to the current
    /// working directory through ``OutputPath``.
    ///
    /// A directory coming from the environment is returned with a trailing
    /// slash so ``OutputPath`` always reads it as a directory — without it, an
    /// extension-less, slash-less path that doesn't yet exist would be
    /// mistaken for a filename.
    ///
    /// - Parameters:
    ///   - explicit: The user-supplied `--output` value, or `nil` when the
    ///     flag was omitted.
    ///   - environment: The environment to inspect. Injectable for tests.
    public static func resolvedOutputTarget(
        explicit: String?,
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let explicit, !explicit.trimmingCharacters(in: .whitespaces).isEmpty {
            return explicit
        }
        guard let raw = environment[EnvironmentKey.outputDirectory],
              !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return raw.hasSuffix("/") ? raw : raw + "/"
    }

    /// The semantic version of the tool, embedded in output metadata.
    public static let toolVersion = "0.2.0"
}
