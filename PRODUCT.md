# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Stack

Native macOS application in Swift. SwiftUI-first, with AppKit where SwiftUI
cannot express the system behavior reliably (status item, floating panels,
window chrome, lifecycle, permission flows). Deployment target macOS 15;
macOS 26 APIs sit behind availability checks.

The code is organized as a SwiftPM package with `VerbiCoreCommon`,
`VerbiCoreDomain`, `VerbiCoreInfrastructure`, `VerbiCoreData`,
`VerbiCoreAudio`, `VerbiCoreAI`, `VerbiCoreUI`, and the `VerbiCore`
aggregation target, consumed by the `Verbi` Xcode app target.

Speech recognition runs on device through FluidAudio, or through a configured
remote provider. AI post-processing and grounded Q&A run through an LLM
provider chosen by the user. Persistence is local: Core Data, UserDefaults,
on-disk audio, and Markdown notes. The meeting-notes editor is a bundled
WKWebView editor built from `Editor/` (CodeMirror 6) and committed as an app
resource, so app builds do not run npm. There is no server component and no
CloudKit synchronization.

## Users

People who dictate text and capture meetings on a Mac and want their audio,
transcripts, and notes to stay on that device. Remote speech and AI providers
are opt-in; a user who configures one accepts that the content needed for that
task is sent to it. The app has no account and no cloud sync, so each install
serves one person on one Mac.

## Product Purpose

Turn speech into text for dictation and meetings, keep a browsable local
history of that speech, and produce notes and summaries — with optional AI
post-processing over the transcript.

## Positioning

A local-first macOS capture and transcription app. On-device transcription on
Apple silicon is the default path; remote speech and AI providers are optional
and explicitly configured. Recordings, transcripts, and notes stay on the Mac.

## Operating Context

- Runs as a menu-bar app. The activation policy always follows the Show in
  Dock preference, including while Settings is open.
- Global keyboard shortcuts and `verbi://` deep links invoke the same actions
  as the menu bar and command router.
- System audio capture uses ScreenCaptureKit and requires Screen Recording
  permission; dictation and meeting microphone audio require Microphone;
  global shortcuts and Assistant actions require Accessibility; reminders read
  the calendar through EventKit and require Calendar; browser integrations
  require Automation for the target browser.
- Local models may download on first use, so the first transcription can take
  minutes. The local path works offline; remote providers require network.
- Apple silicon only. Intel Macs are not supported.
- Distribution is a signed (self-signed identity) but not notarized DMG, also
  published through a Homebrew cask. Gatekeeper may block the first launch of
  a non-notarized build. macOS ties privacy permissions to the signing
  certificate, so the certificate must stay stable across updates.
- An install of the earlier display name (Vozinha, `com.mourato.prisma`)
  migrates its data on first launch; TCC grants do not carry over because they
  are per bundle identifier.

## Capabilities and Constraints

Capabilities:

- Dictation with reusable dictation modes, per-app and per-site routing rules,
  configurable global shortcuts, and text post-processing.
- Meeting capture of microphone and system audio, with detection for Google
  Meet, Microsoft Teams, Slack, and Zoom, plus manual meeting capture.
- Incremental transcription during an active capture to show a live partial
  result before the completed audio file is processed.
- On-device transcription models and remote providers (Groq, ElevenLabs,
  OpenAI).
- Post-processing with per-mode prompt lists and summary strategies, and
  grounded Q&A answered from a capture artifact with transcript evidence.
- Meeting notes tied to a calendar event, a meeting session, or a transcription
  review, flowing into AI post-processing as a context item.
- Proactive meeting reminders driven by EventKit, including a lead-time
  notification and a start-time reminder.
- A local library of capture artifacts with playback, export, and an Activity
  dashboard of recording, dictation, and transcription history.
- File import of existing MP3, M4A, WAV, and AAC recordings.
- Dictionary and vocabulary entries that feed transcription.
- Retention cleanup of old capture audio.
- Light, Dark, and System appearance; language selection; recording-indicator
  options.

Constraints:

- macOS 15 is the floor; newer APIs need availability guards and macOS 15
  fallbacks.
- Apple silicon only; no Intel build.
- No account, no cloud sync, and no content in logs or diagnostics. Network
  access exists only for providers the user configures.
- Calendar reminders read EventKit only; there is no Microsoft Graph or other
  second calendar source, and no Reminders.app integration.
- Retention cleanup deletes capture audio only. Transcripts and artifacts stay.
- Assistant mode records no capture session.
- Secrets live in Keychain.
- Every local model honors `modelResidencyTimeout` and needs a registry entry
  and unload hook.
- The release is not notarized; a notarized distribution would need a paid
  Apple Developer Program membership.

Domain vocabulary is canonical in [GLOSSARY.md](GLOSSARY.md): capture session,
capture purpose, capture mode, dictation style, capture artifact,
post-processing, and the frozen legacy identifiers.

## Brand Commitments

- Product name: Verbi. Bundle identifier `com.mourato.verbi`.
- `MeetingAssistant` is the previous product name and survives only in
  migration inputs and frozen persisted identifiers. `Vozinha` and
  `com.mourato.prisma` are the older display name and technical identity. None
  of them is a separate product, and their persisted values must not change.
- App icon and menu-bar glyph are product assets (`App-Icon.png`,
  `Menubar-Icon.png`), generated into the asset catalog by
  `scripts/generate-app-icon-assets.sh`.
- Documented voice: native, calm, and trustworthy. Recording, permissions,
  configuration, and processing state must always be obvious.
- User-facing text is localized through `.localized` keys, with English and
  Portuguese resources today.

## Evidence on Hand

- Screenshots of Activity, Dictation Modes, and General settings in
  `docs/screenshots/`.
- A Settings preview evidence catalog (`SettingsPreviewEvidenceCatalog`) that
  renders the surfaces at two widths, in dark mode, and with accessibility
  sizing.
- Localized string catalogs for English and Portuguese.
- A SwiftPM test suite under `Packages/VerbiCore/Tests/VerbiCoreTests/`,
  including tests for window layout, motion policy, settings navigation, and
  presentation hosts.

## Product Principles

- Local-first by default: audio, transcripts, and notes stay on the device
  unless the user configures a remote provider for a task.
- Native before custom: macOS semantics, materials, controls, and system colors
  come first; a custom surface needs a reason the native one cannot meet.
- State legibility: capture, transcription, and AI post-processing states stay
  readable at every step, including their failures.
- Calm and trustworthy: the primary task owns the first look; secondary actions
  do not compete with it.
- User control over capture: recording starts from an explicit user action, and
  each reminder layer (lead notification, overlay) can be turned off.
- Accessibility is part of done, not a follow-up.

## Accessibility & Inclusion

The product must stay usable by keyboard alone, with VoiceOver, and with the
macOS accessibility display settings enabled: Light and Dark appearance,
increased contrast, Reduce Transparency, and Reduce Motion. Important state is
never communicated by color alone.
