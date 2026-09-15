import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Integrations Settings Content

/// Content view for Integrations settings, designed for use inside a footerless ModeEditorDrawer.
/// Preserves capability toggle, integration list, editor sheet, and advanced-script sheet.
public struct IntegrationsSettingsContent: View {
    private enum CapabilityLayout {
        static let disabledOpacity = 0.58
    }

    @StateObject private var viewModel = IntegrationSettingsViewModel()
    @StateObject private var settings = AppSettingsStore.shared
    @State private var editingIntegration: AssistantIntegrationConfig?
    @State private var advancedIntegrationDraft: AssistantIntegrationConfig?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        ModeEditorDrawer(
            headerStyle: .close,
            title: "settings.section.integrations".localized,
            iconSymbol: "puzzlepiece.extension",
            onClose: onClose
        ) {
            Form {
                Section {
                    SettingsCapabilityHeaderToggle(
                        titleKey: "settings.capabilities.assistant_integrations",
                        isOn: $settings.isAssistantIntegrationsEnabled
                    )
                }

                integrationsSection
                    .disabled(!isIntegrationsContentEnabled)
                    .opacity(isIntegrationsContentEnabled ? 1 : CapabilityLayout.disabledOpacity)
                    .animation(
                        SettingsMotion.sectionAnimation(reduceMotion: reduceMotion),
                        value: isIntegrationsContentEnabled
                    )
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editingIntegration) { integration in
            AssistantIntegrationEditorSheet(
                integration: integration,
                onApplyAndClose: { draft in
                    if let conflictMessage = viewModel.saveIntegrationWithModifierValidation(draft.integration) {
                        return conflictMessage
                    }
                    editingIntegration = nil
                    return nil
                },
                onDelete: { id in
                    viewModel.removeIntegration(id: id)
                    editingIntegration = nil
                },
                onOpenAdvanced: { draft in
                    advancedIntegrationDraft = draft.integration
                    editingIntegration = nil
                }
            )
        }
        .sheet(item: $advancedIntegrationDraft) { integration in
            AssistantIntegrationBashScriptSheet(
                scriptConfig: integration.advancedScript,
                scriptTestOutput: viewModel.scriptTestOutput,
                scriptTestErrorMessage: viewModel.scriptTestErrorMessage,
                onSave: { scriptConfig in
                    var updated = integration
                    updated.advancedScript = scriptConfig
                    viewModel.saveIntegration(updated)
                    advancedIntegrationDraft = nil
                    viewModel.clearScriptTestResult()
                },
                onTest: { script, input in
                    await viewModel.testScript(script: script, input: input)
                },
                onClose: {
                    advancedIntegrationDraft = nil
                    viewModel.clearScriptTestResult()
                }
            )
        }
    }

    private var integrationsSection: some View {
        AssistantIntegrationsSection(
            viewModel: viewModel,
            showsCapabilityToggle: false,
            editingIntegration: $editingIntegration
        )
    }

    private var isIntegrationsContentEnabled: Bool {
        settings.isAssistantEnabled && settings.isAssistantIntegrationsEnabled
    }
}

#Preview("Integrations Drawer") {
    IntegrationsSettingsContent(onClose: {})
        .frame(width: 400, height: 640)
}
