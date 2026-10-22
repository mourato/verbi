import SwiftUI
import VerbiCoreData
import VerbiCoreDomain

/// Source identity shown in the expanded history-card header.
struct TranscriptionCardSourceLabel: View {
    let transcription: TranscriptionMetadata
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            AppIconView(
                bundleIdentifier: transcription.appBundleIdentifier,
                fallbackSystemName: appSource.icon,
                size: 18,
                cornerRadius: 4
            )
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
    }

    private var appSource: CaptureOrigin {
        CaptureOrigin(rawValue: transcription.appRawValue) ?? .unknown
    }
}
