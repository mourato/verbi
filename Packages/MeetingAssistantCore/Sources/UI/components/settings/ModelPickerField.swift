import MeetingAssistantCoreCommon
import SwiftUI

/// Actionable state shown under a model option; ready models have no status.
struct ModelPickerOptionStatus: Equatable {
    let text: String
    var symbolName: String?
    var isWarning = false

    static var requiresKey: Self {
        Self(text: "settings.models.catalog.badge.requires_key".localized, symbolName: "key", isWarning: true)
    }

    static var notInstalled: Self {
        Self(text: "settings.service.not_installed".localized)
    }
}

/// One selectable model; `value` is what the caller receives on selection.
struct ModelPickerOption<Value>: Identifiable {
    let id: String
    let value: Value
    let title: String
    var subtitle: String?
    let groupTitle: String
    var status: ModelPickerOptionStatus?
    let brand: ModelBrand?
    var host: ModelBrand?
    let fallbackSymbolName: String
    var isSelected = false
    var isEnabled = true
}

/// Form row control: the current model plus a popover list of every option, grouped by provider.
struct ModelPickerField<Value>: View {
    let options: [ModelPickerOption<Value>]
    var onOpen: () -> Void = {}
    let onSelect: (ModelPickerOption<Value>) -> Void

    var fallbackTitle: String = "settings.models.picker.label".localized

    @State private var isPresented = false

    init(
        options: [ModelPickerOption<Value>],
        onOpen: @escaping () -> Void = {},
        fallbackTitle: String = "settings.models.picker.label".localized,
        onSelect: @escaping (ModelPickerOption<Value>) -> Void
    ) {
        self.options = options
        self.onOpen = onOpen
        self.fallbackTitle = fallbackTitle
        self.onSelect = onSelect
    }

    var body: some View {
        Button {
            if !isPresented {
                onOpen()
            }
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                if let selected = options.first(where: \.isSelected) {
                    ModelIdentityView(
                        title: selected.title,
                        subtitle: selected.subtitle ?? selected.groupTitle,
                        brand: selected.brand,
                        host: selected.host,
                        fallbackSymbolName: selected.fallbackSymbolName,
                        size: .compact
                    )
                } else {
                    Text(fallbackTitle)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("settings.models.picker.current".localized(
            with: options.first(where: \.isSelected)?.title ?? fallbackTitle
        ))
        .accessibilityHint("settings.models.picker.hint".localized)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ModelPickerList(options: options) { option in
                isPresented = false
                onSelect(option)
            }
        }
    }
}

/// Searchable, keyboard-navigable model list used inside `ModelPickerField`'s popover.
struct ModelPickerList<Value>: View {
    let options: [ModelPickerOption<Value>]
    let onSelect: (ModelPickerOption<Value>) -> Void

    @State private var query = ""
    @State private var highlightedID: String?
    @FocusState private var isListFocused: Bool

    private static var searchThreshold: Int {
        8
    }

    private var filteredOptions: [ModelPickerOption<Value>] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return options }
        return options.filter {
            $0.title.localizedStandardContains(trimmed) || $0.groupTitle.localizedStandardContains(trimmed)
                || ($0.subtitle?.localizedStandardContains(trimmed) ?? false)
        }
    }

    private var groups: [(title: String, options: [ModelPickerOption<Value>])] {
        var result: [(title: String, options: [ModelPickerOption<Value>])] = []
        for option in filteredOptions {
            if let index = result.firstIndex(where: { $0.title == option.groupTitle }) {
                result[index].options.append(option)
            } else {
                result.append((option.groupTitle, [option]))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if options.count > Self.searchThreshold {
                TextField("settings.models.picker.search".localized, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                    .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                    .onKeyPress(.return) { selectHighlightedOption() }
                    .padding(8)
                Divider()
            }
            ScrollViewReader { proxy in
                ViewThatFits(in: .vertical) {
                    rows
                    ScrollView { rows }
                }
                .onChange(of: highlightedID) { _, id in
                    if let id {
                        proxy.scrollTo(id)
                    }
                }
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 360)
        .focusable()
        .focused($isListFocused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { moveHighlight(by: 1) }
        .onKeyPress(.upArrow) { moveHighlight(by: -1) }
        .onKeyPress(.return) { selectHighlightedOption() }
        .onChange(of: query) { _, _ in
            highlightedID = filteredOptions.first(where: \.isEnabled)?.id
        }
        .onAppear {
            highlightedID = options.first(where: \.isSelected)?.id
            isListFocused = options.count <= Self.searchThreshold
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(groups, id: \.title) { group in
                Text(group.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)
                ForEach(group.options) { option in
                    row(option)
                }
            }
        }
        .padding(6)
    }

    private func row(_ option: ModelPickerOption<Value>) -> some View {
        Button {
            onSelect(option)
        } label: {
            HStack(spacing: 8) {
                ModelIdentityView(
                    title: option.title,
                    subtitle: option.subtitle,
                    brand: option.brand,
                    host: option.host,
                    fallbackSymbolName: option.fallbackSymbolName,
                    size: .compact
                )
                Spacer(minLength: 8)
                if let status = option.status {
                    Label {
                        Text(status.text)
                    } icon: {
                        if let symbolName = status.symbolName {
                            Image(systemName: symbolName)
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(status.isWarning ? AppDesignSystem.Colors.warning : .secondary)
                }
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppDesignSystem.Colors.accent)
                    .opacity(option.isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(highlightedID == option.id ? AppDesignSystem.Colors.subtleFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!option.isEnabled)
        .id(option.id)
        .onHover { isHovering in
            if isHovering {
                highlightedID = option.id
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
    }

    private func selectHighlightedOption() -> KeyPress.Result {
        guard let option = filteredOptions.first(where: { $0.id == highlightedID }), option.isEnabled else {
            return .ignored
        }
        onSelect(option)
        return .handled
    }

    private func moveHighlight(by offset: Int) -> KeyPress.Result {
        let enabled = filteredOptions.filter(\.isEnabled)
        guard !enabled.isEmpty else { return .ignored }
        let current = enabled.firstIndex { $0.id == highlightedID }
        let next = current.map { min(max($0 + offset, 0), enabled.count - 1) } ?? 0
        highlightedID = enabled[next].id
        return .handled
    }
}

#Preview("Model picker field") {
    let options: [ModelPickerOption<String>] = [
        ModelPickerOption(
            id: "local", value: "local", title: "Parakeet TDT v3", groupTitle: "Local",
            brand: .nvidia, fallbackSymbolName: "internaldrive", isSelected: true
        ),
        ModelPickerOption(
            id: "groq", value: "groq", title: "Whisper Large v3 Turbo", groupTitle: "Groq",
            status: .requiresKey, brand: .openai, host: .groq, fallbackSymbolName: "bolt"
        ),
        ModelPickerOption(
            id: "eleven", value: "eleven", title: "Scribe v2", groupTitle: "ElevenLabs",
            brand: .elevenLabs, fallbackSymbolName: "waveform"
        )
    ]
    VStack(alignment: .leading, spacing: 24) {
        Form {
            LabeledContent("Model") {
                ModelPickerField(options: options) { _ in }
            }
        }
        .formStyle(.grouped)
        ModelPickerList(options: options) { _ in }
    }
    .frame(width: 480)
    .padding()
}
