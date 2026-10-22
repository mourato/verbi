import SwiftUI

/// Wraps stateful bindings so interactive controls can run in Xcode previews.
struct PreviewStateContainer<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initialValue: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}

#Preview("Stateful String") {
    PreviewStateContainer("Preview text") { text in
        TextField("Type here", text: text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 320)
    }
    .padding()
}
