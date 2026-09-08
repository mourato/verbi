import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct AssistantIntegrationBashScriptSheet: View {
    @State private var stage: AssistantIntegrationScriptConfig.Stage
    @State private var script: String
    @State private var testInput: String

    private let onSave: (AssistantIntegrationScriptConfig?) -> Void
    private let onTest: (String, String) async -> Void
    private let onClose: () -> Void
    private let scriptTestOutput: String?
    private let scriptTestErrorMessage: String?

    public init(
        scriptConfig: AssistantIntegrationScriptConfig?,
        scriptTestOutput: String?,
        scriptTestErrorMessage: String?,
        onSave: @escaping (AssistantIntegrationScriptConfig?) -> Void,
        onTest: @escaping (String, String) async -> Void,
        onClose: @escaping () -> Void,
    ) {
        _stage = State(initialValue: scriptConfig?.stage ?? .afterAI)
        _script = State(initialValue: scriptConfig?.script ?? "")
        _testInput = State(initialValue: "settings.assistant.integrations.test_message".localized)
        self.scriptTestOutput = scriptTestOutput
        self.scriptTestErrorMessage = scriptTestErrorMessage
        self.onSave = onSave
        self.onTest = onTest
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.assistant.integrations.script.title".localized)
                .font(.title3)
                .fontWeight(.semibold)

            requirementsSection
            stageSection
            examplesSection
            scriptEditorSection
            testSection
            actionsSection
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 620)
    }

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("settings.assistant.integrations.script.requirements".localized)
                .font(.headline)

            Text("settings.assistant.integrations.script.req.stdin".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("settings.assistant.integrations.script.req.stdout".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("settings.assistant.integrations.script.req.timeout".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("settings.assistant.integrations.script.req.empty_output".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.assistant.integrations.script.stage.title".localized)
                .font(.headline)

            Picker("", selection: $stage) {
                ForEach(AssistantIntegrationScriptConfig.Stage.allCases, id: \.self) { currentStage in
                    Text(currentStage.localizedName).tag(currentStage)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.assistant.integrations.script.examples.title".localized)
                .font(.headline)

            HStack(spacing: 8) {
                exampleButton(
                    title: "settings.assistant.integrations.script.examples.word_replace".localized,
                    scriptValue: "sed 's/Verbi/Capta/g'",
                )
                exampleButton(
                    title: "settings.assistant.integrations.script.examples.google_search".localized,
                    scriptValue: "text=$(cat); query=${text// /+}; printf \"https://www.google.com/search?q=%s\" \"$query\"",
                )
                exampleButton(
                    title: "settings.assistant.integrations.script.examples.speak_text".localized,
                    scriptValue: "text=$(cat); say \"$text\"; printf \"%s\" \"$text\"",
                )
                exampleButton(
                    title: "settings.assistant.integrations.script.examples.run_shortcut".localized,
                    scriptValue: "text=$(cat); shortcuts run \"Your Shortcut\" --input-path /dev/stdin <<<\"$text\"; printf \"%s\" \"$text\"",
                )
            }
        }
    }

    private var scriptEditorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.assistant.integrations.script.editor".localized)
                .font(.headline)

            TextEditor(text: $script)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .padding(AppDesignSystem.Layout.textAreaPadding)
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                        .strokeBorder(.separator, lineWidth: 1),
                )
        }
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.assistant.integrations.script.test_input".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("", text: $testInput)
                .textFieldStyle(.roundedBorder)

            if let scriptTestOutput {
                Text("\("settings.assistant.integrations.script.test_output".localized): \(scriptTestOutput)")
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.success)
            }

            if let scriptTestErrorMessage {
                Text(scriptTestErrorMessage)
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.error)
            }
        }
    }

    private var actionsSection: some View {
        HStack {
            Button("settings.assistant.integrations.script.clear".localized, role: .destructive) {
                script = ""
            }
            .foregroundStyle(AppDesignSystem.Colors.error)

            Spacer()

            Button("settings.assistant.integrations.script.test".localized) {
                Task {
                    await onTest(script, testInput)
                }
            }

            Button("settings.assistant.integrations.script.save".localized) {
                let normalized = script.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalized.isEmpty {
                    onSave(nil)
                } else {
                    onSave(AssistantIntegrationScriptConfig(stage: stage, script: normalized))
                }
            }
            .keyboardShortcut(.defaultAction)

            Button("settings.assistant.integrations.editor.close".localized) {
                onClose()
            }
        }
    }

    private func exampleButton(title: String, scriptValue: String) -> some View {
        Button(title) {
            script = scriptValue
        }
        .buttonStyle(.bordered)
    }
}

#Preview("Assistant Integration Bash Script") {
    AssistantIntegrationBashScriptSheet(
        scriptConfig: AssistantIntegrationScriptConfig(stage: .afterAI, script: "cat"),
        scriptTestOutput: "Output",
        scriptTestErrorMessage: nil,
        onSave: { _ in },
        onTest: { _, _ in },
        onClose: {},
    )
}
