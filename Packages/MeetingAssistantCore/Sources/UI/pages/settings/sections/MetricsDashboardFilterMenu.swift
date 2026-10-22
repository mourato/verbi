import SwiftUI

struct MetricsDashboardFilterMenu<SelectionValue: Hashable>: View {
    private let selection: Binding<SelectionValue>
    private let options: [SelectionValue]
    private let maxWidth: CGFloat?
    private let alignment: Alignment
    private let displayName: (SelectionValue) -> String

    init(
        selection: Binding<SelectionValue>,
        options: [SelectionValue],
        maxWidth: CGFloat? = nil,
        alignment: Alignment = .center,
        displayName: @escaping (SelectionValue) -> String
    ) {
        self.selection = selection
        self.options = options
        self.maxWidth = maxWidth
        self.alignment = alignment
        self.displayName = displayName
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    HStack {
                        Text(displayName(option))

                        if selection.wrappedValue == option {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(displayName(selection.wrappedValue))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: maxWidth, alignment: alignment)
            .background(AppDesignSystem.Colors.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.chipCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesignSystem.Layout.chipCornerRadius)
                    .stroke(AppDesignSystem.Colors.separator.opacity(0.6), lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }
}

#Preview("MetricsDashboardFilterMenu") {
    PreviewStateContainer("week") { selection in
        MetricsDashboardFilterMenu(
            selection: selection,
            options: ["day", "week", "month"],
            maxWidth: 120
        ) { value in
            value.capitalized
        }
        .padding()
    }
}
