import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Prompt Editor Sheet

/// Sheet for creating or editing a post-processing prompt.
public struct PromptEditorSheet: View {
    private enum Constants {
        static let sheetWidth: CGFloat = 500
        static let sheetHeight: CGFloat = 550
        static let iconButtonSize: CGFloat = 36
        static let promptEditorMinHeight: CGFloat = 150
    }

    @State private var title: String
    @State private var promptText: String
    @State private var selectedIcon: String
    @State private var description: String

    private let existingPrompt: PostProcessingPrompt?
    private let onSave: (PostProcessingPrompt) -> Void
    private let onCancel: () -> Void

    private var isEditing: Bool {
        existingPrompt != nil
    }

    public init(
        prompt: PostProcessingPrompt?,
        onSave: @escaping (PostProcessingPrompt) -> Void,
        onCancel: @escaping () -> Void
    ) {
        existingPrompt = prompt
        self.onSave = onSave
        self.onCancel = onCancel

        _title = State(initialValue: prompt?.title ?? "")
        _promptText = State(initialValue: prompt?.promptText ?? "")
        _selectedIcon = State(initialValue: prompt?.icon ?? "doc.text.fill")
        _description = State(initialValue: prompt?.description ?? "")
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesignSystem.Layout.sectionSpacing) {
                    titleSection
                    iconSection
                    descriptionSection
                    promptSection
                }
                .padding()
            }

            Divider()

            // Footer
            footer
        }
        .frame(width: Constants.sheetWidth, height: Constants.sheetHeight)
        .background {
            SettingsWindowBackground()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isEditing ? "prompt.edit_title".localized : "prompt.new_title".localized)
                .font(.headline)

            Spacer()
        }
        .padding()
        .background(AppDesignSystem.Colors.settingsGlassBackground)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("prompt.title_label".localized)
                .font(.subheadline)
                .fontWeight(.medium)

            TextField("prompt.title_placeholder".localized, text: $title)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Icon Section

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("prompt.icon_label".localized)
                .font(.subheadline)
                .fontWeight(.medium)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PostProcessingPrompt.availableIcons, id: \.self) { icon in
                        iconButton(icon)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func iconButton(_ icon: String) -> some View {
        let isSelected = selectedIcon == icon

        return Button {
            selectedIcon = icon
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isSelected ? AppDesignSystem.Colors.onAccent : .primary)
                .frame(width: Constants.iconButtonSize, height: Constants.iconButtonSize)
                .background(isSelected ? AppDesignSystem.Colors.accent : AppDesignSystem.Colors.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                        .stroke(isSelected ? AppDesignSystem.Colors.accent : AppDesignSystem.Colors.separator, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("prompt.icon_accessibility".localized(with: icon))
        .accessibilityHint(isSelected ? "prompt.icon_selected".localized : "prompt.icon_select".localized)
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("prompt.description_label".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("common.optional".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("prompt.description_placeholder".localized, text: $description)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("prompt.instructions_label".localized)
                .font(.subheadline)
                .fontWeight(.medium)

            Text("prompt.instructions_hint".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $promptText)
                .font(.body)
                .frame(minHeight: Constants.promptEditorMinHeight)
                .padding(AppDesignSystem.Layout.textAreaPadding)
                .background(AppDesignSystem.Colors.textBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                        .stroke(AppDesignSystem.Colors.separator, lineWidth: 1)
                )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("common.cancel".localized) {
                onCancel()
            }
            .keyboardShortcut(.escape)

            Spacer()

            Button(isEditing ? "common.save".localized : "common.create".localized) {
                savePrompt()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .tint(AppDesignSystem.Colors.accent)
            .disabled(!isValid)
        }
        .padding(16)
        .background(AppDesignSystem.Colors.settingsGlassBackground)
    }

    // MARK: - Validation

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
            !promptText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func savePrompt() {
        let prompt = PostProcessingPrompt(
            id: existingPrompt?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            promptText: promptText.trimmingCharacters(in: .whitespacesAndNewlines),
            isActive: existingPrompt?.isActive ?? false,
            icon: selectedIcon,
            description: description.isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
            isPredefined: false
        )
        onSave(prompt)
    }
}

// MARK: - Preview

#Preview("New Prompt") {
    PromptEditorSheet(
        prompt: nil,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Edit Prompt") {
    PromptEditorSheet(
        prompt: PostProcessingPrompt(
            title: "Resumo Executivo",
            promptText: "Crie um resumo executivo da reunião...",
            icon: "doc.text.magnifyingglass",
            description: "Gera um resumo conciso"
        ),
        onSave: { _ in },
        onCancel: {}
    )
}
