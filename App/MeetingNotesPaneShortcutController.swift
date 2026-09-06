import Combine
import Foundation
import MeetingAssistantCore

@MainActor
final class MeetingNotesPaneShortcutController {
    private let paneController: MeetingNotesPaneController
    private let settings: AppSettingsStore
    private let hotkeyBackend: GlobalHotkeyBackend
    private var cancellables = Set<AnyCancellable>()

    private let hotkeyID = "global.meeting_notes_toggle"
    private var isStarted = false
    private var isRegistered = false
    private var registeredDefinition: ShortcutDefinition?

    init(
        paneController: MeetingNotesPaneController,
        settings: AppSettingsStore = .shared,
        hotkeyBackend: GlobalHotkeyBackend? = nil,
    ) {
        self.paneController = paneController
        self.settings = settings
        self.hotkeyBackend = hotkeyBackend ?? CarbonGlobalHotkeyBackend()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        Publishers.Merge(
            settings.$meetingNotesHotkeyEnabled.map { _ in () },
            settings.$meetingNotesShortcutDefinition.map { _ in () },
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            self?.refresh()
        }
        .store(in: &cancellables)

        refresh()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        unregister()
    }

    func refresh() {
        guard isStarted else { return }

        guard settings.meetingNotesHotkeyEnabled,
              let definition = settings.meetingNotesShortcutDefinition,
              let descriptor = GlobalHotkeyMapper.descriptor(for: definition)
        else {
            unregister()
            return
        }

        guard !isRegistered || registeredDefinition != definition else {
            return
        }

        let registration = HotkeyRegistration(
            id: hotkeyID,
            keyCode: descriptor.keyCode,
            modifiers: descriptor.modifiers,
            onKeyDown: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleHotkey()
                }
            },
            onKeyUp: {},
        )

        hotkeyBackend.registerAll([registration])
        isRegistered = hotkeyBackend.registeredHotkeyCount > 0
        registeredDefinition = isRegistered ? definition : nil
    }

    private func unregister() {
        guard isRegistered || hotkeyBackend.registeredHotkeyCount > 0 else {
            registeredDefinition = nil
            return
        }

        hotkeyBackend.unregisterAll()
        isRegistered = false
        registeredDefinition = nil
    }

    private func handleHotkey() {
        guard settings.meetingNotesHotkeyEnabled else { return }
        paneController.toggle()
    }
}
