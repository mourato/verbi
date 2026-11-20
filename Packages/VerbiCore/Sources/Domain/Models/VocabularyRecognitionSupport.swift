import Foundation

public enum VocabularyRecognitionHelperParameter: String, Sendable, Hashable {
    case none
    case prompt
    case keyterms
}

public struct VocabularyRecognitionSupport: Sendable, Hashable, Equatable {
    public let parameter: VocabularyRecognitionHelperParameter
    public let usedTerms: [String]
    public let partiallySentTerms: [String]
    public let skippedTerms: [String]

    public var usesRecognitionHints: Bool {
        parameter != .none
    }

    public var usedCount: Int {
        usedTerms.count
    }

    public var partiallySentCount: Int {
        partiallySentTerms.count
    }

    public var skippedCount: Int {
        skippedTerms.count
    }

    public init(
        parameter: VocabularyRecognitionHelperParameter,
        snapshot: VocabularySnapshot
    ) {
        self.parameter = parameter

        switch parameter {
        case .none:
            usedTerms = []
            partiallySentTerms = []
            skippedTerms = snapshot.terms.map(\.term)
        case .prompt:
            let wiredPrompt = VocabularyProviderHints.capGroqPrompt(
                snapshot.projectedGroqPrompt()
            ) ?? ""
            var candidate = ""
            var used: [String] = []
            var partial: [String] = []
            var skipped: [String] = []
            var exhausted = false
            for term in snapshot.terms.map(\.term) {
                guard !exhausted else {
                    skipped.append(term)
                    continue
                }
                let fragments = Self.promptFragments(of: term)
                guard !fragments.isEmpty else {
                    skipped.append(term)
                    continue
                }
                let fullContribution = fragments.joined(separator: ", ")
                let fullCandidate = candidate.isEmpty
                    ? fullContribution
                    : candidate + ", " + fullContribution
                if wiredPrompt.hasPrefix(fullCandidate) {
                    used.append(term)
                    candidate = fullCandidate
                    continue
                }
                exhausted = true
                var prefixCandidate = candidate
                var sentFragments = 0
                for fragment in fragments.dropLast() {
                    let next = prefixCandidate.isEmpty
                        ? fragment
                        : prefixCandidate + ", " + fragment
                    guard wiredPrompt.hasPrefix(next) else { break }
                    sentFragments += 1
                    prefixCandidate = next
                }
                guard sentFragments > 0 else {
                    skipped.append(term)
                    continue
                }
                partial.append(term)
            }
            usedTerms = used
            partiallySentTerms = partial
            skippedTerms = skipped
        case .keyterms:
            let used = snapshot.projectedElevenLabsKeyterms()
            usedTerms = used
            partiallySentTerms = []
            skippedTerms = Self.skipped(from: snapshot.terms.map(\.term), used: used)
        }
    }

    private static func promptFragments(of term: String) -> [String] {
        term
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func skipped(from terms: [String], used: [String]) -> [String] {
        let usedSet = Set(used)
        return terms.filter { !usedSet.contains($0) }
    }
}
