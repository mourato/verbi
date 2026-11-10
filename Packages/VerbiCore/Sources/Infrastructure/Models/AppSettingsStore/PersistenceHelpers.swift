import Foundation
import VerbiCoreDomain

extension AppSettingsStore {
    /// Per-occurrence calendar ignores and dismissed reminder keys expire after this window.
    static let calendarKeyRetentionInterval: TimeInterval = 7 * 24 * 60 * 60

    static func isValidHTTPURLString(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            return false
        }

        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(_ value: some Encodable, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func applyLanguage(_ language: AppLanguage) {
        switch language {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .portuguese:
            UserDefaults.standard.set(["pt"], forKey: "AppleLanguages")
        }
    }
}

extension AppSettingsStore: DictionaryPersistenceStore {
    public func persistDictionary(terms: [VocabularyTerm], rules: [VocabularyReplacementRule]) throws {
        let normalizedTerms = Self.normalizedVocabularyTerms(terms)
        let encoder = JSONEncoder()
        let termsData = try encoder.encode(normalizedTerms)
        let rulesData = try encoder.encode(rules)

        UserDefaults.standard.set(termsData, forKey: Keys.vocabularyTerms)
        UserDefaults.standard.set(rulesData, forKey: Keys.vocabularyReplacementRules)

        guard let savedTerms = UserDefaults.standard.data(forKey: Keys.vocabularyTerms),
              savedTerms == termsData,
              let savedRules = UserDefaults.standard.data(forKey: Keys.vocabularyReplacementRules),
              savedRules == rulesData
        else {
            throw DictionaryPersistenceError.saveVerificationFailed
        }

        vocabularyTerms = normalizedTerms
        vocabularyReplacementRules = rules
    }
}
