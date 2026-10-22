import SwiftUI
import VerbiCoreCommon
import VerbiCoreInfrastructure

// preview-check: ignore — picker sheet requires the owning provider registration fixture.

public struct EnhancementsProviderPickerSheet: View {
    let registeredBuiltInProviders: Set<LLMProvider>
    let onSelect: (LLMProvider) -> Void
    let onCancel: () -> Void

    public init(
        registeredBuiltInProviders: Set<LLMProvider>,
        onSelect: @escaping (LLMProvider) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.registeredBuiltInProviders = registeredBuiltInProviders
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            List(LLMProvider.allCases, id: \.self) { provider in
                Button {
                    onSelect(provider)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        EnhancementsProviderAvatar(
                            provider: provider,
                            size: 24,
                            glyphSize: 14
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.displayName)
                                .font(.body)
                                .foregroundStyle(isDisabled(provider) ? .secondary : .primary)

                            Text(providerDescription(for: provider))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if isDisabled(provider) {
                                Text("settings.enhancements.providers.already_added".localized)
                                    .font(.caption2)
                                    .foregroundStyle(AppDesignSystem.Colors.warning)
                            }
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .disabled(isDisabled(provider))
            }
            .navigationTitle("settings.enhancements.providers.select_title".localized)
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

    private func isDisabled(_ provider: LLMProvider) -> Bool {
        provider != .custom && registeredBuiltInProviders.contains(provider)
    }

    private func providerDescription(for provider: LLMProvider) -> String {
        switch provider {
        case .openai:
            "settings.enhancements.provider.openai.desc".localized
        case .anthropic:
            "settings.enhancements.provider.anthropic.desc".localized
        case .groq:
            "settings.enhancements.provider.groq.desc".localized
        case .google:
            "settings.enhancements.provider.google.desc".localized
        case .custom:
            "settings.enhancements.provider.custom.desc".localized
        }
    }
}
