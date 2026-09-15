import AppKit
import Combine
import Foundation
import MeetingAssistantCoreInfrastructure

public struct DictationStyleEditorDraft: Equatable, Sendable {
    public var id: UUID?
    public var name: String
    public var iconSymbol: String
    public var promptInstructions: String
    public var postProcessingEnabled: Bool
    public var forceMarkdownOutput: Bool
    public var replaceBasePrompt: Bool
    public var outputLanguage: DictationOutputLanguage
    public var targets: [DictationStyleTarget]
    public var contextSourcePolicy: DictationContextSourcePolicy?
    public var enhancementsSelection: EnhancementsAISelection?
    public var textHandlingPolicy: DictationTextHandlingPolicy
    public var transcriptionConfiguration: DictationTranscriptionConfiguration
    public var isDefault: Bool

    public init(
        id: UUID? = nil,
        name: String,
        iconSymbol: String,
        promptInstructions: String,
        postProcessingEnabled: Bool = true,
        forceMarkdownOutput: Bool,
        replaceBasePrompt: Bool,
        outputLanguage: DictationOutputLanguage,
        targets: [DictationStyleTarget],
        contextSourcePolicy: DictationContextSourcePolicy?,
        enhancementsSelection: EnhancementsAISelection?,
        textHandlingPolicy: DictationTextHandlingPolicy = .init(),
        transcriptionConfiguration: DictationTranscriptionConfiguration = .init(),
        isDefault: Bool
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.promptInstructions = promptInstructions
        self.postProcessingEnabled = postProcessingEnabled
        self.forceMarkdownOutput = forceMarkdownOutput
        self.replaceBasePrompt = replaceBasePrompt
        self.outputLanguage = outputLanguage
        self.targets = targets
        self.contextSourcePolicy = contextSourcePolicy
        self.enhancementsSelection = enhancementsSelection
        self.textHandlingPolicy = textHandlingPolicy
        self.transcriptionConfiguration = transcriptionConfiguration
        self.isDefault = isDefault
    }
}

@MainActor
public final class DictationStylesSettingsViewModel: ObservableObject {
    @Published public var editorDraft: DictationStyleEditorDraft?
    @Published public private(set) var appCatalog: [InstalledApplicationRecord] = []
    @Published public private(set) var isLoadingAppCatalog = false

    private let settings: AppSettingsStore
    private var cancellables = Set<AnyCancellable>()

    public init(settings: AppSettingsStore = .shared) {
        self.settings = settings

        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var styles: [DictationStyle] {
        settings.dictationStyles
    }

    public func prepareEditor(for styleID: UUID?) {
        if let styleID, let style = settings.dictationStyles.first(where: { $0.id == styleID }) {
            editorDraft = DictationStyleEditorDraft(
                id: style.id,
                name: style.name,
                iconSymbol: style.iconSymbol,
                promptInstructions: style.promptInstructions,
                postProcessingEnabled: style.postProcessingEnabled,
                forceMarkdownOutput: style.forceMarkdownOutput,
                replaceBasePrompt: style.replaceBasePrompt,
                outputLanguage: style.outputLanguage,
                targets: style.targets,
                contextSourcePolicy: style.contextSourcePolicy,
                enhancementsSelection: style.enhancementsSelection,
                textHandlingPolicy: style.textHandlingPolicy,
                transcriptionConfiguration: style.transcriptionConfiguration,
                isDefault: style.isDefault
            )
        } else {
            let defaultStyle = settings.dictationStyles.first(where: \.isDefault)
                ?? settings.currentDefaultDictationStyle()
            editorDraft = DictationStyleEditorDraft(
                name: "",
                iconSymbol: "textformat",
                promptInstructions: "",
                postProcessingEnabled: true,
                forceMarkdownOutput: true,
                replaceBasePrompt: false,
                outputLanguage: .original,
                targets: [],
                contextSourcePolicy: defaultStyle.contextSourcePolicy,
                enhancementsSelection: defaultStyle.enhancementsSelection,
                textHandlingPolicy: defaultStyle.textHandlingPolicy,
                transcriptionConfiguration: defaultStyle.transcriptionConfiguration,
                isDefault: false
            )
        }
        ensureAppCatalogLoaded()
    }

    public func clearEditor() {
        editorDraft = nil
    }

    @discardableResult
    public func saveStyle(_ draft: DictationStyleEditorDraft) -> UUID {
        let persistedID = draft.id ?? UUID()
        let updatedStyle = DictationStyle(
            id: persistedID,
            name: draft.name,
            iconSymbol: draft.iconSymbol,
            promptInstructions: draft.promptInstructions,
            postProcessingEnabled: draft.postProcessingEnabled,
            forceMarkdownOutput: draft.forceMarkdownOutput,
            replaceBasePrompt: draft.replaceBasePrompt,
            outputLanguage: draft.outputLanguage,
            targets: draft.isDefault ? [] : Self.normalizedTargets(draft.targets),
            contextSourcePolicy: draft.contextSourcePolicy,
            enhancementsSelection: draft.enhancementsSelection,
            isDefault: draft.isDefault,
            textHandlingPolicy: draft.textHandlingPolicy,
            transcriptionConfiguration: draft.transcriptionConfiguration
        )

        var updatedStyles = settings.dictationStyles
        if let styleID = draft.id,
           let index = updatedStyles.firstIndex(where: { $0.id == styleID })
        {
            updatedStyles[index] = updatedStyle
        } else {
            updatedStyles.append(updatedStyle)
        }

        settings.dictationStyles = updatedStyles
        clearEditor()
        return persistedID
    }

    public func deleteStyle(id: UUID) {
        settings.dictationStyles.removeAll { $0.id == id }
    }

    public func ensureAppCatalogLoaded() {
        guard appCatalog.isEmpty, !isLoadingAppCatalog else { return }
        isLoadingAppCatalog = true

        Task {
            let discoveredApps = await Task.detached(priority: .userInitiated) {
                AppCatalogDiscovery.discoverInstalledApplications()
            }.value
            appCatalog = discoveredApps
            isLoadingAppCatalog = false
        }
    }

    public func resolveAppDisplayName(bundleIdentifier: String) -> String {
        let normalized = Self.normalizeBundleIdentifier(bundleIdentifier)
        if let known = appCatalog.first(where: { Self.normalizeBundleIdentifier($0.bundleIdentifier) == normalized }) {
            return known.displayName
        }
        return Self.displayName(for: bundleIdentifier)
    }

    public func styleNameConflicting(with target: DictationStyleTarget, excluding styleID: UUID?) -> String? {
        let targetIdentity = Self.targetIdentity(target)

        for style in settings.dictationStyles where style.id != styleID {
            let hasConflict = style.targets.contains { existingTarget in
                Self.targetIdentity(existingTarget) == targetIdentity
            }

            if hasConflict {
                return style.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    public func enhancementsProviderDisplayName(for selection: EnhancementsAISelection) -> String {
        settings.enhancementsProviderDisplayName(for: selection)
    }

    private static func normalizedTargets(_ targets: [DictationStyleTarget]) -> [DictationStyleTarget] {
        var seenKeys = Set<String>()
        var ordered: [DictationStyleTarget] = []

        for target in targets {
            let identity = targetIdentity(target)
            guard !seenKeys.contains(identity) else { continue }

            seenKeys.insert(identity)
            ordered.append(target)
        }

        return ordered
    }

    private static func targetIdentity(_ target: DictationStyleTarget) -> String {
        target.normalizedIdentity
    }

    private static func normalizeBundleIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func displayName(for bundleIdentifier: String) -> String {
        guard
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
            let bundle = Bundle(url: appURL)
        else {
            return bundleIdentifier
        }

        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return appURL.deletingPathExtension().lastPathComponent
    }
}
