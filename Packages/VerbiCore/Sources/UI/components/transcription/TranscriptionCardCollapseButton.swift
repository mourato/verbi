import SwiftUI
import VerbiCoreCommon

struct TranscriptionCardCollapseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("transcription.content.show_less".localized)
        .accessibilityValue("common.expanded".localized)
        .accessibilityAddTraits([.isButton, .isSelected])
    }
}
