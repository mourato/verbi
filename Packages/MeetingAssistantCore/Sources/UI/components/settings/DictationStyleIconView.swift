import SwiftUI

enum DictationStyleIconCatalog {
    static let recommendedSymbols = [
        "textformat",
        "note.text",
        "text.quote",
        "checklist",
        "list.bullet",
        "doc.text",
        "book.closed",
        "lightbulb",
        "briefcase",
        "person.2",
        "bubble.left.and.bubble.right",
        "chevron.left.forwardslash.chevron.right",
        "terminal",
        "hammer",
        "wand.and.stars",
        "graduationcap"
    ]

    static func isEmoji(_ value: String) -> Bool {
        value.count == 1 && value.unicodeScalars.contains(where: { scalar in
            scalar.properties.isEmoji && scalar.value > 127
        })
    }
}

struct DictationStyleIconView: View {
    let iconSymbol: String
    let size: CGFloat
    let accessibilityLabel: String

    var body: some View {
        Group {
            if DictationStyleIconCatalog.isEmoji(iconSymbol) {
                Text(iconSymbol)
                    .font(.system(size: size * 0.82))
            } else {
                Image(systemName: iconSymbol)
                    .font(.system(size: size * 0.82))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    HStack(spacing: 16) {
        DictationStyleIconView(iconSymbol: "note.text", size: 28, accessibilityLabel: "Notes")
        DictationStyleIconView(iconSymbol: "🚀", size: 28, accessibilityLabel: "Rocket")
    }
    .padding()
}
