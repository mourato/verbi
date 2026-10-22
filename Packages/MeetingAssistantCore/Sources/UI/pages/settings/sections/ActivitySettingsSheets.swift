import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import SwiftUI

enum ActivityPresentationSheet: Identifiable, Equatable {
    case moreInsights
    case performance
    case eventDetail(MeetingCalendarEventSnapshot)

    var id: String {
        switch self {
        case .moreInsights:
            "moreInsights"
        case .performance:
            "performance"
        case let .eventDetail(event):
            "eventDetail-\(event.eventIdentifier)"
        }
    }
}

struct ActivityMoreInsightsSheet: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader(title: "metrics.more_insights.title".localized) {
                dismiss()
            }

            MetricsDashboardMoreInsightsPage(viewModel: viewModel)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

struct ActivityPerformanceSheet: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel
    @State private var navigationState = SettingsSubpageNavigationState<MetricsDashboardRoute>()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader(title: "metrics.performance.link.title".localized) {
                dismiss()
            }

            Group {
                switch navigationState.currentRoute {
                case nil:
                    MetricsDashboardPerformancePage { navigationState.open(.performanceRecording($0)) }
                case let .some(.performanceRecording(recordingID)):
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsChildPageBackButton(titleKey: "common.back") {
                            _ = navigationState.goBack()
                        }
                        .padding(.horizontal, 20)

                        MetricsDashboardPerformanceRecordingPage(recordingID: recordingID)
                    }
                default:
                    MetricsDashboardPerformancePage { navigationState.open(.performanceRecording($0)) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 720, minHeight: 520)
        .task {
            await viewModel.load()
        }
    }
}

struct ActivityEventDetailSheet: View {
    let event: MeetingCalendarEventSnapshot
    @ObservedObject var viewModel: MetricsDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader(title: event.title.isEmpty ? "metrics.calendar.upcoming.title".localized : event.title) {
                dismiss()
            }

            MetricsDashboardEventDetailPage(event: event, viewModel: viewModel)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

@ViewBuilder
private func sheetHeader(title: String, onDismiss: @escaping () -> Void) -> some View {
    HStack {
        Text(title)
            .font(.headline)
        Spacer()
        Button("common.done".localized, action: onDismiss)
            .keyboardShortcut(.cancelAction)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background(SettingsTitleBarMaterialBackground())

    Divider()
}
