import SwiftUI

/// Inline meeting-title editor kept independent from the history-card state.
struct TranscriptionMeetingTitleEditor: View {
    let title: String?
    let placeholder: String
    let onCommit: (String?) -> Void

    @State private var draftTitle: String
    @State private var isEditing = false
    @FocusState private var isTitleFieldFocused: Bool

    init(
        title: String?,
        placeholder: String,
        onCommit: @escaping (String?) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.onCommit = onCommit
        _draftTitle = State(initialValue: title ?? "")
    }

    var body: some View {
        Group {
            if isEditing {
                TextField(
                    "",
                    text: $draftTitle,
                    prompt: Text(placeholder)
                )
                .textFieldStyle(.roundedBorder)
                .font(.body.weight(.semibold))
                .focused($isTitleFieldFocused)
                .onSubmit {
                    commit()
                }
                .onChange(of: isTitleFieldFocused) { _, isFocused in
                    if !isFocused {
                        commit()
                    }
                }
                .onExitCommand {
                    cancel()
                }
            } else {
                Button {
                    beginEditing()
                } label: {
                    Text(title ?? placeholder)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: title) { _, _ in
            syncDraftIfNeeded()
        }
    }

    private func beginEditing() {
        draftTitle = title ?? ""
        isEditing = true
        isTitleFieldFocused = true
    }

    private func commit() {
        guard isEditing else { return }

        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        isTitleFieldFocused = false
        draftTitle = trimmedTitle
        onCommit(trimmedTitle.isEmpty ? nil : trimmedTitle)
    }

    private func cancel() {
        guard isEditing else { return }

        isEditing = false
        isTitleFieldFocused = false
        draftTitle = title ?? ""
    }

    private func syncDraftIfNeeded() {
        guard !isEditing else { return }
        draftTitle = title ?? ""
    }
}
