import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct AssistantIntegrationsSection: View {
    @ObservedObject private var viewModel: IntegrationSettingsViewModel
    @ObservedObject private var settings: AppSettingsStore
    private let showsCapabilityToggle: Bool
    @Binding private var editingIntegration: AssistantIntegrationConfig?

    public init(
        viewModel: IntegrationSettingsViewModel,
        settings: AppSettingsStore = .shared,
        showsCapabilityToggle: Bool = true,
        editingIntegration: Binding<AssistantIntegrationConfig?>
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _settings = ObservedObject(wrappedValue: settings)
        self.showsCapabilityToggle = showsCapabilityToggle
        _editingIntegration = editingIntegration
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if showsCapabilityToggle {
                    Toggle(isOn: $settings.isAssistantIntegrationsEnabled) {
                        VStack(alignment: .leading) {
                            Text("settings.capabilities.assistant_integrations".localized)
                            Text("settings.capabilities.assistant_integrations_desc".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                if showsCapabilityToggle {
                    Divider()
                }

                Text("settings.assistant.integrations.description".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Text("settings.assistant.integrations.built_in".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.builtInIntegrations) { integration in
                    integrationRow(integration: integration, isCardStyle: false)
                }

                Divider()

                HStack {
                    Text("settings.assistant.integrations.custom".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        viewModel.addIntegration()
                    } label: {
                        Label(
                            "settings.assistant.integrations.new".localized,
                            systemImage: "plus"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                ForEach(viewModel.customIntegrations) { integration in
                    integrationRow(integration: integration, isCardStyle: true)
                }

                if let statusMessage = viewModel.raycastTestStatusMessage {
                    let statusColor = viewModel.raycastTestStatusIsError
                        ? AppDesignSystem.Colors.error
                        : AppDesignSystem.Colors.success

                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }
        } header: {
            SettingsFormSectionHeader(
                title: "settings.assistant.integrations.title".localized,
                icon: "puzzlepiece.extension"
            )
        }
    }

    private func integrationRow(integration: AssistantIntegrationConfig, isCardStyle: Bool) -> some View {
        HStack(spacing: 12) {
            SettingsRowClickSurface(
                onDoubleClick: {
                    editingIntegration = integration
                },
                content: {
                    HStack(spacing: 12) {
                        if isCardStyle {
                            RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                                .fill(AppDesignSystem.Colors.secondaryFill)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundStyle(.secondary)
                                )
                        }

                        Text(integration.name)
                            .font(.body)
                            .fontWeight(.medium)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("settings.assistant.integrations.shortcut.direct".localized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(shortcutSummary(for: integration))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }

                        Spacer()
                    }
                }
            )

            Button {
                editingIntegration = integration
            } label: {
                Image(systemName: "pencil")
                    .padding(AppDesignSystem.Layout.compactInset)
                    .background(
                        Circle().fill(AppDesignSystem.Colors.secondaryFill)
                    )
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { integration.isEnabled },
                set: { newValue in
                    viewModel.setIntegrationEnabled(newValue, for: integration.id)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(isCardStyle ? 12 : 0)
        .background(
            RoundedRectangle(cornerRadius: AppDesignSystem.Layout.cardCornerRadius)
                .strokeBorder(isCardStyle ? AppDesignSystem.Colors.settingsCardStroke : Color.clear, lineWidth: 1)
        )
    }

    private func shortcutSummary(for integration: AssistantIntegrationConfig) -> String {
        guard let shortcut = integration.shortcutDefinition else {
            return "settings.assistant.integrations.shortcut.not_configured".localized
        }

        let modifierTokens = shortcut.modifiers.map { modifier in
            switch modifier {
            case .leftCommand, .rightCommand, .command:
                "⌘"
            case .leftShift, .rightShift, .shift:
                "⇧"
            case .leftOption, .rightOption, .option:
                "⌥"
            case .leftControl, .rightControl, .control:
                "⌃"
            case .fn:
                "Fn"
            }
        }
        let primary = shortcut.primaryKey?.display ?? ""
        return (modifierTokens + [primary]).joined(separator: " ")
    }
}

#Preview {
    AssistantIntegrationsSection(
        viewModel: IntegrationSettingsViewModel(),
        editingIntegration: .constant(nil)
    )
}
