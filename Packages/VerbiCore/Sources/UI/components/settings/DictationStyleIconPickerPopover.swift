import AppKit
import SwiftUI

struct DictationStyleIconPickerPopover: View {
    @Binding var selection: String
    let onComplete: () -> Void
    @State private var emojiInput = ""
    @State private var validationMessage: String?
    @FocusState private var emojiFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.styles.editor.icon".localized).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                ForEach(availableSymbols, id: \.self) { symbol in
                    Button {
                        selection = symbol
                        onComplete()
                    } label: {
                        Image(systemName: symbol)
                            .frame(width: 44, height: 44)
                            .background(selection == symbol ? AppDesignSystem.Colors.selectionFill : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == symbol ? AppDesignSystem.Colors.selectionStroke : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                    .accessibilityAddTraits(selection == symbol ? [.isSelected] : [])
                }
            }
            Divider()
            HStack {
                TextField("settings.styles.editor.icon".localized, text: $emojiInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($emojiFocused)
                    .onSubmit(addEmoji)
                Button("common.add".localized, action: addEmoji)
                    .buttonStyle(.borderedProminent)
            }
            if let validationMessage {
                Text(validationMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 340)
        .onAppear { emojiFocused = true }
    }

    private func addEmoji() {
        let value = emojiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 1, DictationStyleIconCatalog.isEmoji(value) else {
            validationMessage = "settings.styles.editor.validation.icon_invalid".localized
            return
        }
        selection = value
        validationMessage = nil
        onComplete()
    }

    private var availableSymbols: [String] {
        guard !selection.isEmpty,
              !DictationStyleIconCatalog.recommendedSymbols.contains(selection),
              NSImage(systemSymbolName: selection, accessibilityDescription: nil) != nil
        else {
            return DictationStyleIconCatalog.recommendedSymbols
        }

        return [selection] + DictationStyleIconCatalog.recommendedSymbols
    }
}

#Preview { DictationStyleIconPickerPopover(selection: .constant("note.text"), onComplete: {}) }
