// preview-check: ignore — section components are previewed by DictionaryImportPreviewSheet.

import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

struct DictionaryImportBadgeTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
            .foregroundStyle(color)
    }
}

struct DictionaryImportCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }
}

struct DictionaryImportSectionHeader: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("\(title) (\(count))")
                .font(.subheadline)
                .bold()
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct DictionaryImportAcceptedSectionView: View {
    let preview: DictionaryImportPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DictionaryImportSectionHeader(
                title: "settings.dictionary.import.section.accepted".localized,
                count: preview.totalAcceptedCount,
                color: AppDesignSystem.Colors.success
            )

            ForEach(preview.acceptedTerms) { term in
                DictionaryImportCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term.term)
                                .font(.body)
                                .bold()
                            if !term.definition.isEmpty {
                                Text(term.definition)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        DictionaryImportBadgeTag(
                            text: "settings.dictionary.import.tag.term".localized,
                            color: AppDesignSystem.Colors.success
                        )
                    }
                }
            }

            ForEach(preview.acceptedVariants) { variant in
                DictionaryImportCard {
                    HStack {
                        HStack(spacing: 6) {
                            Text(variant.origin)
                                .font(.body)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(variant.destination.isEmpty ? "(\("settings.dictionary.import.tag.removal".localized))" : variant.destination)
                                .font(.body)
                                .bold()
                        }
                        Spacer()
                        DictionaryImportBadgeTag(
                            text: variant.isNewDestination
                                ? "settings.dictionary.import.tag.new_rule".localized
                                : "settings.dictionary.import.tag.new_variant".localized,
                            color: AppDesignSystem.Colors.success
                        )
                    }
                }
            }
        }
    }
}

struct DictionaryImportConflictsSectionView: View {
    let preview: DictionaryImportPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DictionaryImportSectionHeader(
                title: "settings.dictionary.import.section.conflicts".localized,
                count: preview.totalConflictsCount,
                color: AppDesignSystem.Colors.warning
            )

            ForEach(preview.conflictingVariants) { conflict in
                DictionaryImportCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            HStack(spacing: 6) {
                                Text(conflict.origin)
                                    .font(.body)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text(conflict.candidateDestination)
                                    .font(.body)
                                    .bold()
                            }
                            Spacer()
                            DictionaryImportBadgeTag(
                                text: "settings.dictionary.import.tag.skipped_conflict".localized,
                                color: AppDesignSystem.Colors.warning
                            )
                        }

                        Text(conflictExplanation(for: conflict))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func conflictExplanation(for conflict: DictionaryImportPreview.ConflictingVariantItem) -> String {
        switch conflict.source {
        case .existingDictionary:
            "settings.dictionary.import.conflict_explanation.dictionary".localized(
                with: conflict.origin,
                conflict.existingDestination
            )
        case .earlierInFile:
            "settings.dictionary.import.conflict_explanation.file".localized(
                with: conflict.origin,
                conflict.existingDestination
            )
        }
    }
}

struct DictionaryImportDuplicatesSectionView: View {
    let preview: DictionaryImportPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DictionaryImportSectionHeader(
                title: "settings.dictionary.import.section.duplicates".localized,
                count: preview.totalDuplicatesCount,
                color: .secondary
            )

            ForEach(preview.duplicateTerms) { item in
                DictionaryImportCard {
                    HStack {
                        Text(item.term)
                            .font(.body)
                        Spacer()
                        DictionaryImportBadgeTag(
                            text: item.reason == .alreadyInDictionary
                                ? "settings.dictionary.import.tag.already_exists".localized
                                : "settings.dictionary.import.tag.duplicate_file".localized,
                            color: .secondary
                        )
                    }
                }
            }

            ForEach(preview.duplicateVariants) { item in
                DictionaryImportCard {
                    HStack {
                        HStack(spacing: 6) {
                            Text(item.origin)
                                .font(.body)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(item.destination)
                                .font(.body)
                                .bold()
                        }
                        Spacer()
                        DictionaryImportBadgeTag(
                            text: item.reason == .alreadyInDictionary
                                ? "settings.dictionary.import.tag.already_exists".localized
                                : "settings.dictionary.import.tag.duplicate_file".localized,
                            color: .secondary
                        )
                    }
                }
            }
        }
    }
}

struct DictionaryImportInvalidSectionView: View {
    let preview: DictionaryImportPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DictionaryImportSectionHeader(
                title: "settings.dictionary.import.section.invalid".localized,
                count: preview.totalInvalidCount,
                color: AppDesignSystem.Colors.error
            )

            ForEach(preview.invalidTerms) { item in
                DictionaryImportCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.rawTerm.isEmpty ? "(\("settings.dictionary.import.tag.empty".localized))" : item.rawTerm)
                                .font(.body)
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(AppDesignSystem.Colors.error)
                        }
                        Spacer()
                        DictionaryImportBadgeTag(
                            text: "settings.dictionary.import.tag.invalid".localized,
                            color: AppDesignSystem.Colors.error
                        )
                    }
                }
            }

            ForEach(preview.invalidVariants) { item in
                DictionaryImportCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.origin.isEmpty ? "(\("settings.dictionary.import.tag.empty".localized))" : item.origin)
                                .font(.body)
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(AppDesignSystem.Colors.error)
                        }
                        Spacer()
                        DictionaryImportBadgeTag(
                            text: "settings.dictionary.import.tag.invalid".localized,
                            color: AppDesignSystem.Colors.error
                        )
                    }
                }
            }
        }
    }
}
