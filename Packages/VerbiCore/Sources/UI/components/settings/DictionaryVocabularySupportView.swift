import SwiftUI
import VerbiCoreDomain

/// Truthful, read-only rundown of how the unified word list reaches the
/// currently selected transcription model: which parameter carries the hints,
/// and how many words the request boundary would send, partially send, or
/// drop. All input is precomputed display state, so previews can render
/// fictional data without touching user stores.
public struct DictionaryVocabularySupportView: View {
    public let providerLabel: String
    public let modelLabel: String
    public let support: VocabularyRecognitionSupport

    public init(
        providerLabel: String,
        modelLabel: String,
        support: VocabularyRecognitionSupport
    ) {
        self.providerLabel = providerLabel
        self.modelLabel = modelLabel
        self.support = support
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mainLine)
                    .font(.subheadline)

                if support.partiallySentCount > 0 {
                    Text(
                        "settings.dictionary.words.hints.partial".localized(
                            with: support.partiallySentTerms.joined(separator: ", ")
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }

                if support.skippedCount > 0 {
                    Text(
                        "settings.dictionary.words.hints.skipped".localized(
                            with: support.skippedTerms.joined(separator: ", ")
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            DSInfoPopoverButton(
                title: "settings.dictionary.words.hints.privacy_title".localized,
                message: "settings.dictionary.words.hints.privacy_message".localized
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalCount: Int {
        support.usedCount + support.partiallySentCount + support.skippedCount
    }

    private var mainLine: String {
        let providerAndModel = "\(providerLabel) · \(modelLabel)"
        switch support.parameter {
        case .none:
            return "settings.dictionary.words.hints.local".localized(with: providerAndModel)
        case .prompt, .keyterms:
            return "settings.dictionary.words.hints.remote".localized(
                with: providerAndModel, support.usedCount, totalCount
            )
        }
    }
}

#Preview("Hints — Local") {
    DictionaryVocabularySupportView(
        providerLabel: "Local",
        modelLabel: "Parakeet v3",
        support: VocabularyRecognitionSupport(
            parameter: .none,
            snapshot: VocabularySnapshot(
                terms: [
                    VocabularyTerm(term: "Raycast", definition: ""),
                    VocabularyTerm(term: "FictionalHQ", definition: "")
                ],
                replacementRules: []
            )
        )
    )
    .padding()
    .frame(width: 560)
}

#Preview("Hints — Remote with skips") {
    DictionaryVocabularySupportView(
        providerLabel: "Groq",
        modelLabel: "Whisper Large v3 Turbo",
        support: VocabularyRecognitionSupport(
            parameter: .prompt,
            snapshot: VocabularySnapshot(
                terms: [
                    VocabularyTerm(term: "Raycast", definition: ""),
                    VocabularyTerm(term: "FictionalHQ", definition: "")
                ],
                replacementRules: []
            )
        )
    )
    .padding()
    .frame(width: 560)
}
