import MeetingAssistantCoreCommon
import SwiftUI

public enum SystemSettingsRoute: Hashable, Sendable {
    case root
    case models
    case sound
    case updates
}

public struct SystemSettingsTab: View {
    @Binding private var route: SystemSettingsRoute
    @Binding private var expandProtectedApps: Bool
    private let updatesView: AnyView?
    private let showsUpdateAvailable: Bool

    public init(
        route: Binding<SystemSettingsRoute> = .constant(.root),
        expandProtectedApps: Binding<Bool> = .constant(false),
        updatesView: AnyView? = nil,
        showsUpdateAvailable: Bool = false
    ) {
        _route = route
        _expandProtectedApps = expandProtectedApps
        self.updatesView = updatesView
        self.showsUpdateAvailable = showsUpdateAvailable
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
                headerTitleKey: "settings.section.settings",
                headerDescriptionKey: "settings.system.description",
                openModels: { route = .models },
                openSound: { route = .sound },
                expandProtectedApps: $expandProtectedApps,
                openUpdates: updatesView == nil ? nil : { route = .updates },
                showsUpdateAvailable: showsUpdateAvailable
            )
        case .models:
            ModelsSettingsTab(onBack: { route = .root })
        case .sound:
            AudioSettingsTab(onBack: { route = .root })
        case .updates:
            softwareUpdatesDetail
        }
    }

    @ViewBuilder
    private var softwareUpdatesDetail: some View {
        if let updatesView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsChildPageBackButton { route = .root }
                    .padding(.horizontal, AppDesignSystem.Layout.spacing20)
                    .padding(.top, AppDesignSystem.Layout.spacing20)

                updatesView
            }
        }
    }
}

#Preview {
    SystemSettingsTab()
        .frame(width: 900, height: 620)
}
