import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct WebMeetingTargetEditorSheet: View {
    private let target: WebMeetingTarget?
    private let onSave: (WebMeetingTarget) -> Void
    private let onCancel: () -> Void

    @State private var displayName: String
    @State private var urlPatternsText: String

    public init(
        target: WebMeetingTarget?,
        onSave: @escaping (WebMeetingTarget) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel

        _displayName = State(initialValue: target?.displayName ?? "")
        _urlPatternsText = State(initialValue: (target?.urlPatterns ?? []).joined(separator: "\n"))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.meetings.web_targets.editor_title".localized)
                .font(.headline)

            WebTargetEditorFields(
                nameLabelKey: "settings.meetings.web_targets.name_label",
                urlLabelKey: "settings.meetings.web_targets.url_label",
                urlDescriptionKey: "settings.meetings.web_targets.url_desc",
                canSave: canSave,
                onSave: { onSave(buildTarget()) },
                onCancel: onCancel,
                displayName: $displayName,
                urlPatternsText: $urlPatternsText
            )
        }
        .padding()
        .frame(minWidth: 420)
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !parsedURLPatterns.isEmpty
    }

    private var parsedURLPatterns: [String] {
        WebTargetEditorSupport.parseURLPatterns(from: urlPatternsText)
    }

    private func buildTarget() -> WebMeetingTarget {
        WebMeetingTarget(
            id: target?.id ?? UUID(),
            app: resolvedApp,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            urlPatterns: parsedURLPatterns,
            browserBundleIdentifiers: []
        )
    }

    private var resolvedApp: MeetingApp {
        if let existingApp = target?.app {
            return existingApp
        }

        let normalizedPatterns = parsedURLPatterns.map { $0.lowercased() }
        let matchedDefault = AppSettingsStore.defaultWebMeetingTargets.first { defaultTarget in
            defaultTarget.urlPatterns.contains { defaultPattern in
                normalizedPatterns.contains(where: { $0.contains(defaultPattern.lowercased()) })
            }
        }

        return matchedDefault?.app ?? .manualMeeting
    }
}

#Preview {
    WebMeetingTargetEditorSheet(
        target: AppSettingsStore.defaultWebMeetingTargets.first,
        onSave: { _ in },
        onCancel: {}
    )
}
