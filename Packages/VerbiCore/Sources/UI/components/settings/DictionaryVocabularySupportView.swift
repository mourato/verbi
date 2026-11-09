import SwiftUI
import VerbiCoreDomain

/// Truthful, read-only rundown of how the saved vocabulary reaches the
/// currently selected transcription model. All input is precomputed display
/// state, so previews can render fictional data without touching user stores.
public struct DictionaryVocabularySupportView: View {
    public let providerLabel: String
    public let modelLabel: String
    public let usesRemoteRecognition: Bool
    public let isAIEnhancementOn: Bool
    public let support: VocabularyRecognitionSupport

    public init(
        providerLabel: String,
        modelLabel: String,
        usesRemoteRecognition: Bool,
        isAIEnhancementOn: Bool,
        support: VocabularyRecognitionSupport
    ) {
        self.providerLabel = providerLabel
        self.modelLabel = modelLabel
        self.usesRemoteRecognition = usesRemoteRecognition
        self.isAIEnhancementOn = isAIEnhancementOn
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

            Text(enhancementStateText)
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

    private var enhancementStateText: String {
        if isAIEnhancementOn {
            return "settings.dictionary.vocabulary.support.enhancement.on".localized
        }
        if usesRemoteRecognition {
            return "settings.dictionary.vocabulary.support.enhancement.off.remote".localized
        }
        return "settings.dictionary.vocabulary.support.enhancement.off.local".localized
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
        isAIEnhancementOn: false,
        support: VocabularyRecognitionSupport(
            parameter: .none,
            modelID: "parakeet-tdt-0.6b-v3",
            snapshot: .empty
        )
    )
}

#Preview("Vocabulary Support — Keyterms with skips") {
    DictionaryVocabularySupportView(
        providerLabel: "ElevenLabs",
        modelLabel: "Scribe v2",
        usesRemoteRecognition: true,
        isAIEnhancementOn: true,
        support: VocabularyRecognitionSupport(
            parameter: .keyterms,
            modelID: "scribe_v2",
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
