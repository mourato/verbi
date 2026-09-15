import Foundation
import MeetingAssistantCoreInfrastructure

enum ShortcutDefinitionNormalizer {
    static func normalized(
        _ definition: ShortcutDefinition?,
        allowReturnOrEnter: Bool = true
    ) -> ShortcutDefinition? {
        guard let definition, let primaryKey = definition.primaryKey else {
            return nil
        }

        let isReturnOrEnterKey = primaryKey.keyCode == 0x24 || primaryKey.keyCode == 0x4C
        guard allowReturnOrEnter || !isReturnOrEnterKey else {
            return nil
        }

        let normalized = ShortcutDefinition(
            modifiers: definition.modifiers,
            primaryKey: primaryKey,
            trigger: .singleTap
        )

        return normalized.isValid ? normalized : nil
    }
}
