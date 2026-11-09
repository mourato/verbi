import SwiftUI
import VerbiCoreDomain

/// Truthful, read-only rundown of how the saved vocabulary reaches the
/// currently selected transcription model. All input is precomputed display
/// state, so previews can render fictional data without touching user stores.
public struct DictionaryVocabularySupportView: View {
    public let providerLabel: String
    public let modelLabel: String
    public let usesRemoteRecognition: Bool
    public let support: VocabularyRecognitionSupport

    public init(
        providerLabel: String,
        modelLabel: String,
        usesRemoteRecognition: Bool,
        support: VocabularyRecognitionSupport
    ) {
        self.providerLabel = providerLabel
        self.modelLabel = modelLabel
        self.usesRemoteRecognition = usesRemoteRecognition
        self.support = support
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(providerLabel) · \(modelLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            mechanismLine
                .font(.caption2)
                .foregroundStyle(.secondary)

            if totalCount > 0 {
                Text(
                    "settings.dictionary.vocabulary.support.used".localized(
                        with: support.usedCount, totalCount
                    )
                )
                .font(.caption2)
                .foregroundStyle(.primary)

                if support.skippedCount > 0 {
                    Text(
                        "settings.dictionary.vocabulary.support.skipped".localized(
                            with: support.skippedTerms.joined(separator: ", ")
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }

                if usesRemoteRecognition, support.usedCount > 0 {
                    Text("settings.dictionary.vocabulary.support.remote_disclosure".localized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("settings.dictionary.vocabulary.support.enhancement.conditions".localized)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if usesRemoteRecognition {
                Text("settings.dictionary.vocabulary.support.local_note".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalCount: Int {
        support.usedCount + support.skippedCount
    }

    @ViewBuilder
    private var mechanismLine: some View {
        switch support.parameter {
        case .none:
            Text("settings.dictionary.vocabulary.support.mechanism.local".localized)
        case .prompt:
            Text(
                "settings.dictionary.vocabulary.support.mechanism.prompt".localized(
                    with: VocabularyProviderHints.groqMaxCharacters
                )
            )
        case .keyterms:
            Text(
                "settings.dictionary.vocabulary.support.mechanism.keyterms".localized(
                    with: VocabularyProviderHints.elevenLabsMaxCharactersPerTerm
                )
            )
        }
    }
}

#Preview("Vocabulary Support — Local, no terms") {
    DictionaryVocabularySupportView(
        providerLabel: "Local",
        modelLabel: "Parakeet v3",
        usesRemoteRecognition: false,
        support: VocabularyRecognitionSupport(
            parameter: .none,
            snapshot: .empty
        )
    )
}

#Preview("Vocabulary Support — Keyterms with skips") {
    DictionaryVocabularySupportView(
        providerLabel: "ElevenLabs",
        modelLabel: "Scribe v2",
        usesRemoteRecognition: true,
        support: VocabularyRecognitionSupport(
            parameter: .keyterms,
            snapshot: VocabularySnapshot(
                terms: [
                    VocabularyTerm(term: "SwiftUI", definition: ""),
                    VocabularyTerm(term: "FictionalHQ", definition: "")
                ],
                replacementRules: []
            )
        )
    )
}
