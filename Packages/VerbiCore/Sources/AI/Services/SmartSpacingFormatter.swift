import Foundation
import VerbiCoreDomain

public enum SmartSpacingFormatter {
    public static func format(dictatedText: String, cursorContext: CursorTextContext) -> String {
        guard !dictatedText.isEmpty else { return dictatedText }

        switch cursorContext.support {
        case .permissionDenied:
            return appendTrailingSpaceIfNeeded(to: dictatedText)
        case .unsupported:
            return dictatedText
        case .supported:
            break
        }

        guard !cursorContext.isEmptyDocument else { return dictatedText }

        var output = dictatedText

        if shouldLowercaseFirstCharacter(previousCharacter: cursorContext.previousCharacter) {
            output = lowercasingFirstCharacter(in: output)
        }

        if shouldAddLeadingSpace(previousCharacter: cursorContext.previousCharacter) {
            output = prependLeadingSpaceIfNeeded(to: output)
        }

        if shouldAddTrailingSpace(nextCharacter: cursorContext.nextCharacter) {
            output = appendTrailingSpaceIfNeeded(to: output)
        }

        return output
    }

    private static func shouldAddLeadingSpace(previousCharacter: Character?) -> Bool {
        guard let previousCharacter else { return false }
        return isWordCharacter(previousCharacter) || isSentenceTerminator(previousCharacter)
    }

    private static func shouldAddTrailingSpace(nextCharacter: Character?) -> Bool {
        guard let nextCharacter else { return false }
        return isWordCharacter(nextCharacter)
    }

    private static func shouldLowercaseFirstCharacter(previousCharacter: Character?) -> Bool {
        guard let previousCharacter else { return false }
        guard isWordCharacter(previousCharacter) else { return false }
        return !isSentenceTerminator(previousCharacter)
    }

    private static func lowercasingFirstCharacter(in text: String) -> String {
        guard let firstCharacter = text.first else { return text }
        let lowercased = String(firstCharacter).lowercased()
        return lowercased + text.dropFirst()
    }

    private static func appendTrailingSpaceIfNeeded(to text: String) -> String {
        guard text.last != " " else { return text }
        return text + " "
    }

    private static func prependLeadingSpaceIfNeeded(to text: String) -> String {
        guard text.first != " " else { return text }
        return " " + text
    }

    private static func isSentenceTerminator(_ character: Character) -> Bool {
        character == "." || character == "?" || character == "!"
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }
}
