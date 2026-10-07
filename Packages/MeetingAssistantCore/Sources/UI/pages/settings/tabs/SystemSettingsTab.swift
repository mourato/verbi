import MeetingAssistantCoreCommon
import SwiftUI

public struct SystemSettingsTab: View {
    @Binding private var expandProtectedApps: Bool

    public init(
        expandProtectedApps: Binding<Bool> = .constant(false)
    ) {
        _expandProtectedApps = expandProtectedApps
    }

    public var body: some View {
        GeneralSettingsTab(
            showsHeader: true,
            headerTitleKey: "settings.section.general",
            headerDescriptionKey: "settings.system.description",
            expandProtectedApps: $expandProtectedApps
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    SystemSettingsTab()
        .frame(width: 900, height: 620)
}
