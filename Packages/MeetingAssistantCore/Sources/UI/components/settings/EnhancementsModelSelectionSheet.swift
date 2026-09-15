import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct EnhancementsModelSelectionSheet: View {
    private struct ProviderGroup: Identifiable {
        struct Key: Hashable {
            let provider: AIProvider
            let registrationID: UUID?
            let title: String
        }

        let key: Key
        var options: [EnhancementsProviderModelOption]

        var id: String {
            let registrationPart = key.registrationID?.uuidString ?? key.provider.rawValue
            return "\(registrationPart)::\(key.title)"
        }
    }

    let options: [EnhancementsProviderModelOption]
    let isSelected: (EnhancementsProviderModelOption) -> Bool
    let onSelect: (EnhancementsProviderModelOption) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    public init(
        options: [EnhancementsProviderModelOption],
        isSelected: @escaping (EnhancementsProviderModelOption) -> Bool,
        onSelect: @escaping (EnhancementsProviderModelOption) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.options = options
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("settings.enhancements.model_selector.title".localized)
                        .font(.headline)

                    Spacer(minLength: 8)

                    searchField
                        .frame(width: 320)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                List {
                    ForEach(groupedFilteredOptions) { group in
                        Section {
                            ForEach(group.options, id: \.id) { option in
                                optionRow(option)
                            }
                        } header: {
                            Text(group.key.title)
                                .font(.caption)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) {
                        onCancel()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var filteredOptions: [EnhancementsProviderModelOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter { option in
            option.modelID.localizedCaseInsensitiveContains(query)
                || option.provider.displayName.localizedCaseInsensitiveContains(query)
                || option.registrationName?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var groupedFilteredOptions: [ProviderGroup] {
        let sortedOptions = filteredOptions.sorted { lhs, rhs in
            let lhsName = lhs.registrationName ?? lhs.provider.displayName
            let rhsName = rhs.registrationName ?? rhs.provider.displayName

            if lhsName.caseInsensitiveCompare(rhsName) == .orderedSame {
                return lhs.modelID.localizedCaseInsensitiveCompare(rhs.modelID) == .orderedAscending
            }

            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        var groupsByKey: [ProviderGroup.Key: [EnhancementsProviderModelOption]] = [:]
        var orderedKeys: [ProviderGroup.Key] = []

        for option in sortedOptions {
            let key = ProviderGroup.Key(
                provider: option.provider,
                registrationID: option.registrationID,
                title: option.registrationName ?? option.provider.displayName
            )

            if groupsByKey[key] == nil {
                orderedKeys.append(key)
                groupsByKey[key] = []
            }

            groupsByKey[key, default: []].append(option)
        }

        return orderedKeys.compactMap { key in
            guard let groupedOptions = groupsByKey[key], !groupedOptions.isEmpty else {
                return nil
            }

            return ProviderGroup(
                key: key,
                options: groupedOptions
            )
        }
    }

    private func optionRow(_ option: EnhancementsProviderModelOption) -> some View {
        Button {
            onSelect(option)
        } label: {
            HStack(spacing: 8) {
                Text(option.modelID)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected(option) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppDesignSystem.Colors.success)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "settings.enhancements.model_selector.search_placeholder".localized,
                text: $searchText
            )
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: AppDesignSystem.Layout.compactButtonHeight)
        .background(AppDesignSystem.Colors.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
    }
}

#Preview("Enhancements model selector") {
    let options: [EnhancementsProviderModelOption] = [
        .init(provider: .openai, modelID: "gpt-4o-mini"),
        .init(provider: .openai, modelID: "gpt-4o"),
        .init(provider: .anthropic, modelID: "claude-3-5-sonnet"),
        .init(provider: .google, modelID: "gemini-1.5-flash")
    ]

    EnhancementsModelSelectionSheet(
        options: options,
        isSelected: { option in
            option.modelID == "gpt-4o"
        },
        onSelect: { _ in },
        onCancel: {}
    )
    .frame(width: 560, height: 440)
}
