import SwiftUI

/// A compact native menu picker for controls that do not live in a `Form` row.
///
/// Settings forms should use a direct, visibly labelled `Picker` instead so
/// macOS can provide the native row layout and accessibility semantics. Use
/// this wrapper for compact filters, dashboards, and fixed-width action rows.
public struct DSMenuPicker<SelectionValue: Hashable, Content: View>: View {
    private let title: String
    private let selection: Binding<SelectionValue>
    private let width: CGFloat?
    private let minWidth: CGFloat?
    private let maxWidth: CGFloat?
    private let alignment: Alignment
    private let content: Content

    public init(
        _ title: String = "",
        selection: Binding<SelectionValue>,
        width: CGFloat? = nil,
        minWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.selection = selection
        self.width = width
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.alignment = alignment
        self.content = content()
    }

    public var body: some View {
        Picker(title, selection: selection) {
            content
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: width, alignment: alignment)
        .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: alignment)
    }
}

#Preview("DSMenuPicker") {
    PreviewStateContainer("hybrid") { selection in
        DSMenuPicker("Shortcut Mode", selection: selection, width: 120) {
            Text("Hybrid").tag("hybrid")
            Text("Toggle").tag("toggle")
            Text("Hold").tag("hold")
        }
        .padding()
    }
}
