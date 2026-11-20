import Foundation

public enum InputSanitizer {
    public static func sanitizeFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:;.")
        let sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")

        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty || trimmed.allSatisfy({ $0 == "_" }) {
            return "unnamed_\(UUID().uuidString.prefix(8))"
        }

        return trimmed
    }

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
