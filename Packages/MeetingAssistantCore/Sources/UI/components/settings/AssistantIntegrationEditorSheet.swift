import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct AssistantIntegrationEditorDraft: Equatable {
    public var integration: AssistantIntegrationConfig

    public init(integration: AssistantIntegrationConfig) {
        self.integration = integration
    }
}

public struct AssistantIntegrationEditorSheet: View {
    private enum Constants {
        static let copyFeedbackDurationNanoseconds: UInt64 = 1_500_000_000
    }

    @State private var draft: AssistantIntegrationEditorDraft
    @State private var copiedPlaceholderToken: String?
    @State private var copiedFeedbackTask: Task<Void, Never>?
    @State private var activePlaceholderPopoverToken: String?
    @State private var shortcutConflictMessage: String?
    private let onApplyAndClose: (AssistantIntegrationEditorDraft) -> String?
    private let onDelete: (UUID) -> Void
    private let onOpenAdvanced: (AssistantIntegrationEditorDraft) -> Void

    public init(
        integration: AssistantIntegrationConfig,
        onApplyAndClose: @escaping (AssistantIntegrationEditorDraft) -> String?,
        onDelete: @escaping (UUID) -> Void,
        onOpenAdvanced: @escaping (AssistantIntegrationEditorDraft) -> Void
    ) {
        _draft = State(initialValue: AssistantIntegrationEditorDraft(integration: integration))
        self.onApplyAndClose = onApplyAndClose
        self.onDelete = onDelete
        self.onOpenAdvanced = onOpenAdvanced
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.assistant.integrations.editor.title.integration".localized)
                .font(.title3)
                .fontWeight(.semibold)

            if !isBuiltInIntegration {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.assistant.integrations.integration_name".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("", text: $draft.integration.name)
                        .textFieldStyle(.roundedBorder)
                }
            }

            DSModifierShortcutEditor(
                shortcut: Binding(
                    get: { draft.integration.shortcutDefinition },
                    set: { draft.integration.shortcutDefinition = $0 }
                ),
                conflictMessage: shortcutConflictMessage
            )

            if !isBuiltInIntegration {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.assistant.integrations.integration_deeplink".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("", text: $draft.integration.deepLink)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("settings.assistant.integrations.editor.instructions".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: Binding(
                    get: { draft.integration.promptInstructions ?? "" },
                    set: { draft.integration.promptInstructions = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 90)
                .padding(AppDesignSystem.Layout.textAreaPadding)
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                        .strokeBorder(.separator, lineWidth: 1)
                )
            }

            overlayVisibilitySection

            if !isBuiltInIntegration {
                placeholderSection

                Button(action: { onOpenAdvanced(draft) }) {
                    Label("settings.assistant.integrations.editor.advanced".localized, systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .padding(.vertical, 12)
            }

            HStack {
                if !isBuiltInIntegration {
                    Button(role: .destructive) {
                        onDelete(draft.integration.id)
                    } label: {
                        Text("settings.assistant.integrations.editor.delete".localized)
                    }
                    .foregroundStyle(AppDesignSystem.Colors.error)
                }

                Spacer()

                Button("settings.assistant.integrations.editor.close".localized) {
                    shortcutConflictMessage = onApplyAndClose(draft)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 480)
        .onChange(of: draft.integration.shortcutDefinition) { _, _ in
            shortcutConflictMessage = nil
        }
        .onDisappear {
            copiedFeedbackTask?.cancel()
        }
    }

    private var isBuiltInIntegration: Bool {
        draft.integration.id == AssistantIntegrationConfig.raycastDefaultID
    }

    private var overlayVisibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.assistant.integrations.editor.overlay_visibility.title".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("settings.assistant.integrations.editor.overlay_visibility.description".localized)
                .font(.caption2)
                .foregroundStyle(.secondary)

            SettingsCheckboxRow(
                "settings.assistant.integrations.editor.overlay_visibility.prompt.title".localized,
                description: "settings.assistant.integrations.editor.overlay_visibility.prompt.description".localized,
                isOn: Binding(
                    get: { draft.integration.showsPromptSelectorInOverlay },
                    set: { draft.integration.showsPromptSelectorInOverlay = $0 }
                )
            )

            SettingsCheckboxRow(
                "settings.assistant.integrations.editor.overlay_visibility.language.title".localized,
                description: "settings.assistant.integrations.editor.overlay_visibility.language.description".localized,
                isOn: Binding(
                    get: { draft.integration.showsLanguageSelectorInOverlay },
                    set: { draft.integration.showsLanguageSelectorInOverlay = $0 }
                )
            )
        }
    }

    private var placeholderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.assistant.integrations.editor.placeholders.title".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("settings.assistant.integrations.editor.placeholders.subtitle".localized)
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                placeholderButton(token: AssistantIntegrationDeepLinkShortcode.finalText)
                placeholderButton(token: AssistantIntegrationDeepLinkShortcode.finalTextURLEncoded)
                placeholderButton(token: AssistantIntegrationDeepLinkShortcode.rawText)
                placeholderButton(token: AssistantIntegrationDeepLinkShortcode.rawTextURLEncoded)
            }

            if let copiedPlaceholderToken {
                Text(
                    String(
                        format: "settings.assistant.integrations.editor.placeholders.copied".localized,
                        copiedPlaceholderToken
                    )
                )
                .font(.caption)
                .foregroundStyle(AppDesignSystem.Colors.success)
            }
        }
    }

    private func placeholderButton(token: String) -> some View {
        let isUsedInDeepLink = draft.integration.deepLink.contains(token)
        let isJustCopied = copiedPlaceholderToken == token

        return HStack(spacing: 6) {
            Button {
                copyPlaceholder(token)
            } label: {
                HStack(spacing: 6) {
                    Text(token)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(isUsedInDeepLink ? Color.accentColor : Color.primary)

                    Spacer()

                    Image(systemName: isUsedInDeepLink ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(isUsedInDeepLink ? Color.accentColor : Color.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                        .fill(isUsedInDeepLink ? AppDesignSystem.Colors.accent.opacity(0.12) : AppDesignSystem.Colors.subtleFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                        .strokeBorder(isUsedInDeepLink ? AppDesignSystem.Colors.accent.opacity(0.55) : AppDesignSystem.Colors.settingsCardStroke, lineWidth: 1)
                )
                .opacity(isJustCopied ? 0.9 : 1)
            }
            .buttonStyle(.plain)
            .help("settings.assistant.integrations.editor.placeholders.copy_help".localized)

            Button {
                activePlaceholderPopoverToken = token
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("settings.assistant.integrations.editor.placeholders.info_help".localized)
            .popover(
                isPresented: Binding(
                    get: { activePlaceholderPopoverToken == token },
                    set: { isPresented in
                        if !isPresented {
                            activePlaceholderPopoverToken = nil
                        }
                    }
                ),
                arrowEdge: .bottom
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(token)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(placeholderMeaning(for: token))
                        .font(.callout)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("settings.assistant.integrations.editor.placeholders.example_title".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(placeholderExample(for: token))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .frame(width: 300, alignment: .leading)
            }
        }
    }

    private func placeholderMeaning(for token: String) -> String {
        switch token {
        case AssistantIntegrationDeepLinkShortcode.finalText:
            "settings.assistant.integrations.editor.placeholders.final_text.meaning".localized
        case AssistantIntegrationDeepLinkShortcode.finalTextURLEncoded:
            "settings.assistant.integrations.editor.placeholders.final_text_urlencoded.meaning".localized
        case AssistantIntegrationDeepLinkShortcode.rawText:
            "settings.assistant.integrations.editor.placeholders.raw_text.meaning".localized
        case AssistantIntegrationDeepLinkShortcode.rawTextURLEncoded:
            "settings.assistant.integrations.editor.placeholders.raw_text_urlencoded.meaning".localized
        default:
            ""
        }
    }

    private func placeholderExample(for token: String) -> String {
        switch token {
        case AssistantIntegrationDeepLinkShortcode.finalText:
            "settings.assistant.integrations.editor.placeholders.final_text.example".localized
        case AssistantIntegrationDeepLinkShortcode.finalTextURLEncoded:
            "settings.assistant.integrations.editor.placeholders.final_text_urlencoded.example".localized
        case AssistantIntegrationDeepLinkShortcode.rawText:
            "settings.assistant.integrations.editor.placeholders.raw_text.example".localized
        case AssistantIntegrationDeepLinkShortcode.rawTextURLEncoded:
            "settings.assistant.integrations.editor.placeholders.raw_text_urlencoded.example".localized
        default:
            ""
        }
    }

    private func copyPlaceholder(_ token: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)

        copiedFeedbackTask?.cancel()
        copiedPlaceholderToken = token

        copiedFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.copyFeedbackDurationNanoseconds)
            copiedPlaceholderToken = nil
        }
    }
}

#Preview("Assistant Integration Editor") {
    AssistantIntegrationEditorSheet(
        integration: AssistantIntegrationConfig.defaultRaycast,
        onApplyAndClose: { _ in nil },
        onDelete: { _ in },
        onOpenAdvanced: { _ in }
    )
}
