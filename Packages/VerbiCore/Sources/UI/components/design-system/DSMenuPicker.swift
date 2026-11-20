import SwiftUI

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
