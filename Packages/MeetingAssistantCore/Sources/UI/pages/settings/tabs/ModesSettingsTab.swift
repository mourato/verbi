import MeetingAssistantCoreAI
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct ModesSettingsTab: View {
    @StateObject private var viewModel: DictationStylesSettingsViewModel
    @StateObject private var aiSettingsViewModel: AISettingsViewModel
    @State private var navigationState = SettingsSubpageNavigationState<DictationStyleRoute>()
    @FocusState private var focusedStyle: DictationStyleFocusTarget?
    @AccessibilityFocusState private var accessibilityFocusedStyle: DictationStyleFocusTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modesReduceMotionPreview) private var reduceMotionPreview
    @Binding private var initialRoute: DictationStyleRoute?

    public init(settings: AppSettingsStore = .shared, initialRoute: Binding<DictationStyleRoute?> = .constant(nil)) {
        _viewModel = StateObject(wrappedValue: DictationStylesSettingsViewModel(settings: settings))
        _aiSettingsViewModel = StateObject(wrappedValue: AISettingsViewModel(settings: settings))
        _initialRoute = initialRoute
    }

    public var body: some View {
        listColumn
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .settingsSidePanel(
                isPresented: isEditorPresented,
                onDismiss: dismissPresentedRoute,
                onEscape: handleEscapeShortcut
            ) {
                if let route = navigationState.currentRoute {
                    routeContent(for: route)
                        .id(route)
                        .focusSection()
                }
            }
            .onAppear {
                consumeInitialRoute()
            }
            .onChange(of: initialRoute) { _, newValue in
                if newValue != nil {
                    consumeInitialRoute()
                }
            }
    }

    private func consumeInitialRoute() {
        guard let route = initialRoute else { return }
        initialRoute = nil
        openRoute(route)
    }

    private var isEditorPresented: Bool {
        navigationState.currentRoute != nil
    }

    private var listColumn: some View {
        StylesSettingsTab(
            viewModel: viewModel,
            aiSettingsViewModel: aiSettingsViewModel,
            focusedStyle: $focusedStyle,
            accessibilityFocusedStyle: $accessibilityFocusedStyle,
            isListFocusEnabled: !isEditorPresented,
            onOpenEditor: { styleID in
                viewModel.prepareEditor(for: styleID)
                focusedStyle = nil
                accessibilityFocusedStyle = nil
                openRoute(.editor(styleID: styleID))
            },
            onOpenAssistant: {
                focusedStyle = nil
                accessibilityFocusedStyle = nil
                openRoute(.assistant)
            },
            onOpenIntegrations: {
                focusedStyle = nil
                accessibilityFocusedStyle = nil
                openRoute(.integrations)
            }
        )
    }

    @ViewBuilder
    private func routeContent(for route: DictationStyleRoute) -> some View {
        switch route {
        case let .editor(styleID):
            editorPage(styleID: styleID)
        case let .promptEditor(styleID):
            promptEditorPage(styleID: styleID)
        case .assistant:
            AssistantSettingsContent(onClose: dismissPresentedRoute)
        case .integrations:
            IntegrationsSettingsContent(onClose: dismissPresentedRoute)
        }
    }

    @ViewBuilder
    private func editorPage(styleID: UUID?) -> some View {
        if let draft = viewModel.editorDraft {
            DictationStyleEditorDetailView(
                draft: draft,
                appCatalog: viewModel.appCatalog,
                isLoadingAppCatalog: viewModel.isLoadingAppCatalog,
                onEnsureAppCatalogLoaded: viewModel.ensureAppCatalogLoaded,
                onFindConflictingStyleName: { target, excludeID in
                    viewModel.styleNameConflicting(with: target, excluding: excludeID)
                },
                modelOptions: aiSettingsViewModel.enhancementsProviderModels,
                isLoadingModelOptions: aiSettingsViewModel.isLoadingEnhancementsProviderModels,
                onRefreshModelOptions: { _ = aiSettingsViewModel.refreshEnhancementsProviderModelsManually() },
                providerDisplayName: viewModel.enhancementsProviderDisplayName(for:),
                onSave: { draft in
                    let savedID = viewModel.saveStyle(draft)
                    closePanel(focusTarget: .style(savedID))
                },
                onCancel: dismissPresentedRoute,
                onDelete: styleID == nil ? nil : {
                    if let styleID {
                        viewModel.deleteStyle(id: styleID)
                    }
                    viewModel.clearEditor()
                    closePanel(focusTarget: .addButton)
                },
                onOpenPromptEditor: { draft in
                    viewModel.editorDraft = draft
                    openRoute(.promptEditor(styleID: styleID))
                }
            )
        }
    }

    @ViewBuilder
    private func promptEditorPage(styleID: UUID?) -> some View {
        if let draft = viewModel.editorDraft {
            DictationStylePromptEditorView(
                promptInstructions: Binding(
                    get: { draft.promptInstructions },
                    set: { viewModel.editorDraft?.promptInstructions = $0 }
                ),
                onCancel: { openRoute(.editor(styleID: styleID)) }
            )
        }
    }

    private func dismissPresentedRoute() {
        guard let route = navigationState.currentRoute else { return }
        switch route {
        case .editor, .promptEditor:
            viewModel.clearEditor()
        case .assistant, .integrations:
            break
        }
        closePanel(focusTarget: route.dismissFocusTarget)
    }

    private func handleEscapeShortcut() {
        guard let route = navigationState.currentRoute else { return }
        switch route.escapeBehavior {
        case let .returnToEditor(styleID):
            openRoute(.editor(styleID: styleID))
        case .dismissPanel:
            dismissPresentedRoute()
        }
    }

    private func closePanel(focusTarget: DictationStyleFocusTarget) {
        withAnimation(SettingsMotion.sidePanelAnimation(reduceMotion: effectiveReduceMotion)) {
            _ = navigationState.goBack()
        }
        focusedStyle = focusTarget
        accessibilityFocusedStyle = focusTarget
    }

    private func openRoute(_ route: DictationStyleRoute) {
        withAnimation(SettingsMotion.sidePanelAnimation(reduceMotion: effectiveReduceMotion)) {
            navigationState.open(route)
        }
    }

    private var effectiveReduceMotion: Bool {
        reduceMotion || reduceMotionPreview
    }
}

#Preview("Modes — Drawer") { ModesSettingsTab().frame(width: 900, height: 640) }
#Preview("Modes — Narrow") { ModesSettingsTab().frame(width: 620, height: 520) }
#Preview("Modes — Accessibility") {
    ModesSettingsTab()
        .frame(width: 820, height: 620)
        .environment(\.dynamicTypeSize, .accessibility3)
        .environment(\.modesReduceMotionPreview, true)
        .environment(\.settingsReduceTransparencyPreview, true)
        .preferredColorScheme(.dark)
}

private extension EnvironmentValues {
    @Entry var modesReduceMotionPreview: Bool = false
}
