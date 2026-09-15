import AppKit
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

// preview-check: ignore — editor presentation requires the provider registration fixture.

public enum EnhancementsProviderEditorMode {
    case create
    case edit
}

public struct EnhancementsProviderEditorSheet: View {
    static let curatedCustomProviderIcons: [String] = [
        "server.rack",
        "network",
        "cloud",
        "terminal",
        "cpu",
        "bolt.horizontal",
        "link",
        "shield",
        "lock",
        "key",
        "antenna.radiowaves.left.and.right",
        "globe",
        "gearshape",
        "shippingbox",
        "puzzlepiece",
        "wrench.and.screwdriver",
        "sparkles",
        "brain",
        "text.bubble",
        "wave.3.right"
    ]

    let mode: EnhancementsProviderEditorMode
    let provider: AIProvider
    @Binding var displayName: String
    @Binding var baseURL: String
    @Binding var iconSystemName: String?
    @Binding var apiKey: String
    let hasSavedAPIKey: Bool
    let connectionStatus: ConnectionStatus
    let errorMessage: String?
    let onSave: () -> Void
    let onTestAndSave: () -> Void
    let onDelete: (() -> Void)?
    let onRemoveKey: (() -> Void)?
    let onCancel: () -> Void

    public init(
        mode: EnhancementsProviderEditorMode,
        provider: AIProvider,
        displayName: Binding<String>,
        baseURL: Binding<String>,
        iconSystemName: Binding<String?>,
        apiKey: Binding<String>,
        hasSavedAPIKey: Bool,
        connectionStatus: ConnectionStatus,
        errorMessage: String?,
        onSave: @escaping () -> Void,
        onTestAndSave: @escaping () -> Void,
        onDelete: (() -> Void)?,
        onRemoveKey: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.provider = provider
        _displayName = displayName
        _baseURL = baseURL
        _iconSystemName = iconSystemName
        _apiKey = apiKey
        self.hasSavedAPIKey = hasSavedAPIKey
        self.connectionStatus = connectionStatus
        self.errorMessage = errorMessage
        self.onSave = onSave
        self.onTestAndSave = onTestAndSave
        self.onDelete = onDelete
        self.onRemoveKey = onRemoveKey
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            providerHeader

            if provider == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.enhancements.providers.editor.name".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.ai.base_url".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://api.example.com/v1", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                customIconSelector
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("settings.ai.api_key".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if hasSavedAPIKey {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(AppDesignSystem.Colors.success)
                        Text("settings.ai.keychain_secure".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if let onRemoveKey {
                            Button("settings.enhancements.providers.editor.remove_api_and_edit".localized, role: .destructive) {
                                onRemoveKey()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } else {
                    SecureField("settings.ai.api_key_placeholder".localized, text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let apiURL = provider.apiKeyURL {
                Button("settings.ai.get_api_key".localized) {
                    NSWorkspace.shared.open(apiURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(connectionStatus.color)
                    .frame(width: 7, height: 7)
                Text(connectionStatus.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage, !errorMessage.isEmpty {
                DSCallout(
                    kind: .warning,
                    title: "settings.enhancements.provider_models.error.title".localized,
                    message: errorMessage
                )
            }

            HStack {
                if let onDelete {
                    Button("common.delete".localized, role: .destructive) {
                        onDelete()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("common.cancel".localized) {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("common.save".localized) {
                    onSave()
                }
                .buttonStyle(.bordered)

                Button("settings.enhancements.test_and_save".localized) {
                    onTestAndSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(connectionStatus == .testing || (!hasSavedAPIKey && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(20)
        .frame(minWidth: 560)
    }

    private var title: String {
        switch mode {
        case .create:
            "settings.enhancements.providers.editor.title_create".localized
        case .edit:
            "settings.enhancements.providers.editor.title_edit".localized
        }
    }

    private var providerHeader: some View {
        HStack(spacing: 10) {
            EnhancementsProviderAvatar(
                provider: provider,
                customIconName: provider == .custom ? resolvedCustomIconSystemName : nil,
                size: 30,
                glyphSize: 16
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.headline)
                Text("settings.enhancements.providers.editor.provider_label".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var customIconSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.enhancements.providers.editor.icon".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("settings.enhancements.providers.editor.icon_help".localized)
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 24), spacing: 8), count: 5),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(Self.curatedCustomProviderIcons, id: \.self) { symbolName in
                    iconOptionButton(symbolName)
                }
            }
        }
    }

    private func iconOptionButton(_ symbolName: String) -> some View {
        let isSelected = resolvedCustomIconSystemName == symbolName

        return Button {
            iconSystemName = symbolName
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(isSelected ? AppDesignSystem.Colors.accent : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                        .fill(isSelected ? AppDesignSystem.Colors.accent.opacity(0.14) : AppDesignSystem.Colors.subtleFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                        .strokeBorder(
                            isSelected ? AppDesignSystem.Colors.accent : AppDesignSystem.Colors.separator.opacity(0.5),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .help(symbolName)
        .accessibilityLabel(symbolName)
    }

    private var resolvedCustomIconSystemName: String {
        let normalizedIconSystemName = iconSystemName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedIconSystemName,
              Self.curatedCustomProviderIcons.contains(normalizedIconSystemName)
        else {
            return provider.icon
        }

        return normalizedIconSystemName
    }
}
