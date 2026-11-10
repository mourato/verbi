import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

struct DictionaryImportPreviewSheet: View {
    let preview: DictionaryImportPreview
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var selectedFilter: PreviewFilter = .all

    enum PreviewFilter: String, CaseIterable, Identifiable {
        case all
        case accepted
        case conflicts
        case duplicates
        case invalid

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .all:
                "settings.dictionary.import.tab.all".localized
            case .accepted:
                "settings.dictionary.import.tab.accepted".localized
            case .conflicts:
                "settings.dictionary.import.tab.conflicts".localized
            case .duplicates:
                "settings.dictionary.import.tab.duplicates".localized
            case .invalid:
                "settings.dictionary.import.tab.invalid".localized
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Divider()

            summaryBadgesView
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider()

            filterPickerView
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

            Divider()

            contentListView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footerView
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 480, idealHeight: 560)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(AppDesignSystem.Colors.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("settings.dictionary.import.preview.title".localized)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text("settings.dictionary.import.preview.description".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Summary Badges

    private var summaryBadgesView: some View {
        HStack(spacing: 12) {
            badge(
                label: "settings.dictionary.import.badge.accepted".localized,
                count: preview.totalAcceptedCount,
                systemImage: "checkmark.circle.fill",
                color: AppDesignSystem.Colors.success
            )
            badge(
                label: "settings.dictionary.import.badge.conflicts".localized,
                count: preview.totalConflictsCount,
                systemImage: "exclamationmark.triangle.fill",
                color: AppDesignSystem.Colors.warning
            )
            badge(
                label: "settings.dictionary.import.badge.duplicates".localized,
                count: preview.totalDuplicatesCount,
                systemImage: "doc.on.doc.fill",
                color: .secondary
            )
            badge(
                label: "settings.dictionary.import.badge.invalid".localized,
                count: preview.totalInvalidCount,
                systemImage: "xmark.circle.fill",
                color: preview.totalInvalidCount > 0 ? AppDesignSystem.Colors.error : .secondary
            )
        }
    }

    private func badge(label: String, count: Int, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text("\(label):")
                .foregroundStyle(.secondary)
            Text("\(count)")
                .bold()
                .foregroundStyle(.primary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(count)")
    }

    // MARK: - Filter Picker

    private var filterPickerView: some View {
        HStack {
            Picker("settings.dictionary.import.preview.filter_label".localized, selection: $selectedFilter) {
                ForEach(PreviewFilter.allCases) { filter in
                    Text(filterTitle(for: filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("settings.dictionary.import.preview.filter_label".localized)

            Spacer()
        }
    }

    private func filterTitle(for filter: PreviewFilter) -> String {
        switch filter {
        case .all:
            "\(filter.title) (\(preview.totalAcceptedCount + preview.totalConflictsCount + preview.totalDuplicatesCount + preview.totalInvalidCount))"
        case .accepted:
            "\(filter.title) (\(preview.totalAcceptedCount))"
        case .conflicts:
            "\(filter.title) (\(preview.totalConflictsCount))"
        case .duplicates:
            "\(filter.title) (\(preview.totalDuplicatesCount))"
        case .invalid:
            "\(filter.title) (\(preview.totalInvalidCount))"
        }
    }

    // MARK: - Content List

    private var contentListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !preview.hasImportableChanges, selectedFilter == .all {
                    emptyNoticeView
                }

                if shouldShowSection(.accepted), preview.totalAcceptedCount > 0 {
                    DictionaryImportAcceptedSectionView(preview: preview)
                }

                if shouldShowSection(.conflicts), preview.totalConflictsCount > 0 {
                    DictionaryImportConflictsSectionView(preview: preview)
                }

                if shouldShowSection(.duplicates), preview.totalDuplicatesCount > 0 {
                    DictionaryImportDuplicatesSectionView(preview: preview)
                }

                if shouldShowSection(.invalid), preview.totalInvalidCount > 0 {
                    DictionaryImportInvalidSectionView(preview: preview)
                }

                if isCurrentFilterEmpty {
                    Text("settings.dictionary.import.empty_filter".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(20)
        }
    }

    private var emptyNoticeView: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .font(.title3)
                .accessibilityHidden(true)

            Text("settings.dictionary.import.no_new_entries".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func shouldShowSection(_ filter: PreviewFilter) -> Bool {
        selectedFilter == .all || selectedFilter == filter
    }

    private var isCurrentFilterEmpty: Bool {
        switch selectedFilter {
        case .all:
            preview.totalAcceptedCount == 0 &&
                preview.totalConflictsCount == 0 &&
                preview.totalDuplicatesCount == 0 &&
                preview.totalInvalidCount == 0
        case .accepted:
            preview.totalAcceptedCount == 0
        case .conflicts:
            preview.totalConflictsCount == 0
        case .duplicates:
            preview.totalDuplicatesCount == 0
        case .invalid:
            preview.totalInvalidCount == 0
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if preview.hasImportableChanges {
                Text("settings.dictionary.import.preview.summary".localized(with: preview.acceptedTerms.count, preview.acceptedVariants.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("common.cancel".localized, role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button("settings.dictionary.import.action_confirm".localized, action: onConfirm)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!preview.hasImportableChanges)
        }
    }
}

#Preview {
    DictionaryImportPreviewSheet(
        preview: DictionaryImportPreview(
            sourceApp: "Verbi",
            exportDate: "2026-03-24T18:00:00Z",
            baseTermsSnapshot: [],
            baseRulesSnapshot: [],
            termsSummary: DictionaryImportPreview.EntrySummary(acceptedCount: 1, duplicateCount: 0, conflictingCount: 0, invalidCount: 0),
            variantsSummary: DictionaryImportPreview.EntrySummary(acceptedCount: 1, duplicateCount: 0, conflictingCount: 0, invalidCount: 0),
            acceptedTerms: [VocabularyTerm(term: "Verbi", definition: "App")],
            duplicateTerms: [],
            invalidTerms: [],
            acceptedVariants: [DictionaryImportPreview.AcceptedVariantItem(origin: "verby", destination: "Verbi", isNewDestination: true)],
            duplicateVariants: [],
            conflictingVariants: [],
            invalidVariants: [],
            mergedTerms: [VocabularyTerm(term: "Verbi", definition: "App")],
            mergedRules: [VocabularyReplacementRule(find: "verby", replace: "Verbi")]
        ),
        onConfirm: {},
        onCancel: {}
    )
}
