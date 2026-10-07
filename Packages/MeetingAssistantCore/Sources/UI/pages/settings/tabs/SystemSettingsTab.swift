import MeetingAssistantCoreCommon
import SwiftUI

public enum SystemSettingsRoute: Hashable, Sendable {
    case root
}

public struct SystemSettingsTab: View {
    @Binding private var route: SystemSettingsRoute
    @Binding private var expandProtectedApps: Bool

    public init(
        route: Binding<SystemSettingsRoute> = .constant(.root),
        expandProtectedApps: Binding<Bool> = .constant(false)
    ) {
        _route = route
        _expandProtectedApps = expandProtectedApps
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @MainActor
    @ViewBuilder
    private var content: some View {
        switch route {
        case .root:
            GeneralSettingsTab(
                showsHeader: true,
                headerTitleKey: "settings.section.general",
                headerDescriptionKey: "settings.system.description",
                expandProtectedApps: $expandProtectedApps
            )
        }
    }
}

#Preview {
    SystemSettingsTab()
        .frame(width: 900, height: 620)
}
