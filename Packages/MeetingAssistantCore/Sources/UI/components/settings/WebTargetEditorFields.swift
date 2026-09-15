import MeetingAssistantCoreCommon
import SwiftUI

struct WebTargetEditorFields<AdditionalContent: View>: View {
    let nameLabelKey: String
    let urlLabelKey: String
    let urlDescriptionKey: String
    let canSave: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    let additionalContent: AdditionalContent

    @Binding var displayName: String
    @Binding var urlPatternsText: String

    init(
        nameLabelKey: String,
        urlLabelKey: String,
        urlDescriptionKey: String,
        canSave: Bool,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        displayName: Binding<String>,
        urlPatternsText: Binding<String>,
        @ViewBuilder additionalContent: () -> AdditionalContent
    ) {
        self.nameLabelKey = nameLabelKey
        self.urlLabelKey = urlLabelKey
        self.urlDescriptionKey = urlDescriptionKey
        self.canSave = canSave
        self.onSave = onSave
        self.onCancel = onCancel
        _displayName = displayName
        _urlPatternsText = urlPatternsText
        self.additionalContent = additionalContent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(nameLabelKey.localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(urlLabelKey.localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(urlDescriptionKey.localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextEditor(text: $urlPatternsText)
                    .font(.caption.monospaced())
                    .frame(minHeight: 80)
                    .padding(AppDesignSystem.Layout.textAreaPadding)
                    .background(AppDesignSystem.Colors.subtleFill2)
                    .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
            }

            additionalContent

            HStack {
                Spacer()
                Button("common.cancel".localized) {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("common.save".localized) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
    }
}

extension WebTargetEditorFields where AdditionalContent == EmptyView {
    init(
        nameLabelKey: String,
        urlLabelKey: String,
        urlDescriptionKey: String,
        canSave: Bool,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        displayName: Binding<String>,
        urlPatternsText: Binding<String>
    ) {
        self.init(
            nameLabelKey: nameLabelKey,
            urlLabelKey: urlLabelKey,
            urlDescriptionKey: urlDescriptionKey,
            canSave: canSave,
            onSave: onSave,
            onCancel: onCancel,
            displayName: displayName,
            urlPatternsText: urlPatternsText
        ) {
            EmptyView()
        }
    }
}

#Preview {
    struct EditorPreviewState {
        var displayName: String
        var urlPatternsText: String
    }

    return PreviewStateContainer(
        EditorPreviewState(
            displayName: "Docs",
            urlPatternsText: "docs.example.com"
        )
    ) { state in
        WebTargetEditorFields(
            nameLabelKey: "settings.meetings.web_targets.name_label",
            urlLabelKey: "settings.meetings.web_targets.url_label",
            urlDescriptionKey: "settings.meetings.web_targets.url_desc",
            canSave: true,
            onSave: {},
            onCancel: {},
            displayName: Binding(
                get: { state.wrappedValue.displayName },
                set: { state.wrappedValue.displayName = $0 }
            ),
            urlPatternsText: Binding(
                get: { state.wrappedValue.urlPatternsText },
                set: { state.wrappedValue.urlPatternsText = $0 }
            )
        )
        .padding()
    }
}
