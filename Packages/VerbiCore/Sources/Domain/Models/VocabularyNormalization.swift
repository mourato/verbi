import Foundation

public enum VocabularyNormalization {
    public static func spelling(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    public static func destinationKey(_ value: String) -> String {
        spelling(value)
    }

    public static func originKey(_ value: String) -> String {
        spelling(value).lowercased()
    }

    public static func termKey(_ value: String) -> String {
        spelling(value).lowercased()
    }
}
