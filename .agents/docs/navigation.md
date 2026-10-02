# Navigation

Use `codegraph_explore` first for indexed source, naming these entry files or
symbols to follow callers and module boundaries. If an isolated worktree has
no index, use conventional search there; an index from another checkout does
not prove worktree freshness. Use file reads for docs, scripts, manifests, and
configuration gaps. Keep commands in [Build and Test Reference](build-and-test.md)
and skill locations in [Skill Routing Guide](skill-routing.md).

## Flow Entry Points

Paths below are relative to `Packages/MeetingAssistantCore/Sources/` unless
prefixed with `App/` or `scripts/`. These are starting points, not a file inventory.

| Task | Entry points |
| --- | --- |
| Capture and device recovery | `UI/Services/RecordingManager/RecordingManager.swift`; `Audio/Services/AudioRecorder/AudioRecorder.swift` and `AudioRecorderDeviceRecovery.swift` in the same directory |
| Capture failure/lifecycle | `UI/Services/RecordingManager/RecordingLifecycleCoordinator.swift` and `LifecycleHelpers.swift` in the same directory |
| Transcription to history | `UI/Services/RecordingManager/RecordingManagerTranscriptionPipeline.swift`; `UI/ViewModels/TranscriptionSettingsViewModel/TranscriptionSettingsViewModel.swift` |
| Notes panel/editor | `UI/Presentation/MeetingNotesPaneController.swift`; `UI/components/settings/MeetingNotesMarkdownEditor.swift`; `UI/components/meeting-notes/MeetingNotesEditorWebView.swift` |
| Dock/settings | `App/AppDelegate/AppDelegateUserInterfacePreferences.swift`; `UI/pages/settings/SettingsPage.swift`; `UI/components/settings/SettingsWindowConfigurator.swift` |
| Deep links | `App/AppDelegate/DeepLinks.swift`; `Common/Utilities/AppDeepLink.swift`; `App/MeetingAssistantApp.swift` (`AppCommandRouter`) |
| App icon generation | [Wrapper](../../scripts/generate-app-icon-assets.sh): defaults to [App-Icon.png](../../App-Icon.png), writes [AppIcon.appiconset](../../App/Assets.xcassets/AppIcon.appiconset) |
| Menu-bar icon | [Artwork](../../Menubar-Icon.png); [asset catalog](../../App/Assets.xcassets/MenubarIcon.imageset); status-item owner `App/AppDelegate/MenuBar.swift` |

UI invariants live in [docs/ui.md](../../docs/ui.md), not in this entry-point map.

## Dependencies

- Swift declarations and target ownership: [core Package.swift](../../Packages/MeetingAssistantCore/Package.swift).
  App-level package references: [Xcode project](../../MeetingAssistant.xcodeproj/project.pbxproj).
- Resolved Swift versions: package `Package.resolved` beside its manifest;
  workspace `MeetingAssistant.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
  These lockfiles are ignored by Git and can be absent in a fresh worktree;
  declarations constrain versions but do not prove what another checkout resolved.
- SwiftPM sources: package `.build/checkouts` for ordinary SwiftPM;
  `.tmp/swiftpm-agent/checkouts` for the agent runner, overridden by
  `MA_SWIFTPM_SCRATCH_PATH`. Xcode sources: `.xcode-build/SourcePackages/checkouts`,
  overridden by `VALIDATE_DERIVED_DATA_PATH`; strict parity uses its own temporary
  DerivedData or `MA_XCODE_STRICT_DERIVED_DATA`. Validate-lane uses per-run roots
  and removes them. Inspect the active runner path before searching caches.
- Web editor declarations/resolved versions: [package.json](../../Editor/package.json)
  and [package-lock.json](../../Editor/package-lock.json); installed sources are
  under `Editor/node_modules` after installation.

Use Codegraph to find library consumers; use the active lockfile to identify
resolved versions. A cache in another worktree is evidence about that worktree,
not this one. Run the documented task runner when resolution/build is needed.
