import MeetingAssistantCoreCommon
import SwiftUI

/// Three-zone content anatomy used by the Modes side panel.
public struct ModeEditorDrawer<Content: View>: View {
    public enum HeaderStyle { case close, back, backWithAction }

    private let headerStyle: HeaderStyle
    private let title: String
    private let iconSymbol: String
    private let name: Binding<String>?
    private let onIconPicker: (() -> Void)?
    private let actionTitle: String
    private let onClose: (() -> Void)?
    private let onBack: (() -> Void)?
    private let onAction: (() -> Void)?
    private let footerLeadingAction: (() -> Void)?
    private let footerTrailingTitle: String
    private let footerTrailingAction: () -> Void
    private let content: Content
    @FocusState private var isNameFocused: Bool
    @AccessibilityFocusState private var isNameAccessibilityFocused: Bool

    public init(
        headerStyle: HeaderStyle,
        title: String,
        iconSymbol: String = "",
        name: Binding<String>? = nil,
        onIconPicker: (() -> Void)? = nil,
        actionTitle: String = "",
        onClose: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onAction: (() -> Void)? = nil,
        footerLeadingAction: (() -> Void)? = nil,
        footerTrailingTitle: String = "",
        footerTrailingAction: @escaping () -> Void = {},
        @ViewBuilder content: () -> Content
    ) {
        self.headerStyle = headerStyle
        self.title = title
        self.iconSymbol = iconSymbol
        self.name = name
        self.onIconPicker = onIconPicker
        self.actionTitle = actionTitle
        self.onClose = onClose
        self.onBack = onBack
        self.onAction = onAction
        self.footerLeadingAction = footerLeadingAction
        self.footerTrailingTitle = footerTrailingTitle
        self.footerTrailingAction = footerTrailingAction
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if showsFooter {
                footer
            }
        }
    }

    private var showsFooter: Bool {
        footerLeadingAction != nil || !footerTrailingTitle.isEmpty
    }

    private var header: some View {
        HStack(spacing: 10) {
            switch headerStyle {
            case .close:
                if let name, let onIconPicker {
                    Button {
                        onIconPicker()
                    } label: {
                        DictationStyleIconView(iconSymbol: iconSymbol, size: 24, accessibilityLabel: "settings.styles.editor.icon".localized)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(AppDesignSystem.Colors.subtleFill2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("settings.styles.editor.icon_picker".localized)
                    TextField("settings.styles.editor.name".localized, text: name)
                        .textFieldStyle(.plain)
                        .font(.headline.weight(.semibold))
                        .focused($isNameFocused)
                        .accessibilityFocused($isNameAccessibilityFocused)
                        .accessibilityLabel("settings.styles.editor.name".localized)
                } else if !iconSymbol.isEmpty {
                    DictationStyleIconView(iconSymbol: iconSymbol, size: 24, accessibilityLabel: title)
                        .frame(width: 36, height: 36)
                    Text(title).font(.headline.weight(.semibold)).lineLimit(1)
                } else {
                    Text(title).font(.headline.weight(.semibold)).lineLimit(1)
                }
                Spacer()
                if let onClose {
                    closeButton(onClose)
                }
            case .back:
                if let onBack {
                    backButton(onBack)
                }
                Text(title).font(.headline.weight(.semibold)).lineLimit(1)
                Spacer()
            case .backWithAction:
                if let onBack {
                    backButton(onBack)
                }
                Text(title).font(.headline.weight(.semibold)).lineLimit(1)
                Spacer()
                if let onAction {
                    Button(actionTitle, action: onAction).buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear {
            if headerStyle == .close, name != nil {
                isNameFocused = true
                isNameAccessibilityFocused = true
            }
        }
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button("settings.styles.editor.close".localized, systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("settings.styles.editor.close".localized)
    }

    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button("common.back".localized, systemImage: "chevron.left", action: action)
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
    }

    private var footer: some View {
        HStack {
            if let footerLeadingAction {
                Button(role: .destructive, action: footerLeadingAction) {
                    Label(footerTrailingTitle == "common.create".localized ? "common.cancel".localized : "common.delete".localized, systemImage: footerTrailingTitle == "common.create".localized ? "xmark" : "trash")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            if !footerTrailingTitle.isEmpty {
                Button(footerTrailingTitle, action: footerTrailingAction)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(name?.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
            }
        }
        .padding(14)
        .overlay(alignment: .top) { Divider() }
    }
}

#Preview("Drawer") {
    ModeEditorDrawer(
        headerStyle: .close,
        title: "Daily Notes",
        iconSymbol: "note.text",
        onClose: {},
        content: {
            Form { Text("Grouped form content") }.formStyle(.grouped)
        }
    )
    .frame(width: 400, height: 500)
}
