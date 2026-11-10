import Foundation

/// One normalization vocabulary for every dictionary text surface: creation,
/// editing, reading persisted values, and archive import.
///
/// Displayed spellings keep their letters and case. Only outer whitespace is
/// trimmed and canonically equivalent Unicode forms are composed, so a legacy
/// decomposed spelling and a composed spelling compare as the same value.
public enum VocabularyNormalization {
    /// Trims outer whitespace and canonicalizes Unicode composition for display.
    public static func spelling(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    /// Destinations keep case: `US` and `us` are deliberately different entries.
    public static func destinationKey(_ value: String) -> String {
        spelling(value)
    }

    /// Origins match case-insensitively, as transcript substitution already does.
    public static func originKey(_ value: String) -> String {
        spelling(value).lowercased()
    }

    /// Vocabulary hints keep the app's existing case-insensitive identity.
    public static func termKey(_ value: String) -> String {
        spelling(value).lowercased()
    }
}
