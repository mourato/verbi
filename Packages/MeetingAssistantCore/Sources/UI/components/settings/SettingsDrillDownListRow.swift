import SwiftUI

public struct SettingsDrillDownListRow<Destination: Hashable>: View {
    private let destination: Destination
    private let title: String
    private let subtitle: String?
    private let accessibilityHint: String?

    public init(
        destination: Destination,
        title: String,
        subtitle: String? = nil,
        accessibilityHint: String? = nil
    ) {
        self.destination = destination
        self.title = title
        self.subtitle = subtitle
        self.accessibilityHint = accessibilityHint
    }

    public var body: some View {
        NavigationLink(value: destination) {
            SettingsDrillDownRowLabel(title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .modifier(OptionalAccessibilityHintModifier(accessibilityHint: accessibilityHint))
    }
}

public struct SettingsDrillDownButtonRow: View {
    private let title: String
    private let subtitle: String?
    private let accessibilityHint: String?
    private let action: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            SettingsDrillDownRowLabel(title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .modifier(OptionalAccessibilityHintModifier(accessibilityHint: accessibilityHint))
    }
}

private struct SettingsDrillDownRowLabel: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 8) {
            SettingsTitleWithPopover(
                title: title,
                helperMessage: subtitle
            )

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

private struct OptionalAccessibilityHintModifier: ViewModifier {
    let accessibilityHint: String?

    func body(content: Content) -> some View {
        if let accessibilityHint, !accessibilityHint.isEmpty {
            content.accessibilityHint(accessibilityHint)
        } else {
            content
        }
    }
}

#Preview("Drill-Down Row") {
    NavigationStack {
        SettingsDrillDownListRow(
            destination: 1,
            title: "Monitored apps and sites",
            subtitle: "Configure which apps and web targets are monitored to detect meetings automatically."
        )
        .padding()
        .navigationDestination(for: Int.self) { _ in
            Text("Detail")
        }
    }
}
