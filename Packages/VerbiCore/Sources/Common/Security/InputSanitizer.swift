import Foundation

/// Utility for sanitizing user inputs and filenames to prevent security issues.
public enum InputSanitizer {
    /// Sanitizes a string to be used as a safe filename component.
    /// Removes traversal characters and replaced invalid characters with underscores.
    public static func sanitizeFilename(_ name: String) -> String {
        // Remove path traversal and invalid characters
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:;.")
        let sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")

        // Remove leading/trailing spaces and dots
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure it's not empty and not just underscores
        if trimmed.isEmpty || trimmed.allSatisfy({ $0 == "_" }) {
            return "unnamed_\(UUID().uuidString.prefix(8))"
        }

        return trimmed
    }

    /// Validates that a filename component is safe.
    /// - Throws: An error if the component is unsafe.
    public static func validatePathComponent(_ component: String) throws {
        if component.contains("..") || component.contains("/") || component.contains("\\") {
            throw InputSanitizerError.unsafePath(component)
        }
    }
}

public enum InputSanitizerError: LocalizedError {
    case unsafePath(String)

    public var errorDescription: String? {
        switch self {
        case let .unsafePath(path):
            "Unsafe path component detected: \(path)"
        }
    }
}
