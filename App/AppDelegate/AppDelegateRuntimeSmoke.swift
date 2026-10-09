import AppKit
import MeetingAssistantCore

extension AppDelegate {
    #if DEBUG
        func scheduleRuntimeSmokeIfRequested() {
            guard ProcessInfo.processInfo.environment["MA_RUNTIME_SMOKE"] == "recording-start" else { return }

            Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                await self?.runRuntimeRecordingSmoke()
            }
        }

        private func runRuntimeRecordingSmoke() async {
            print("RUNTIME_SMOKE: START recording-start")
            await startRecording(source: .microphone)

            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                if recordingManager.isRecording {
                    await recordingManager.cancelRecording()
                    print("RUNTIME_SMOKE: PASS recording-start")
                    NSApp.terminate(nil)
                    return
                }

                if recordingManager.lastError != nil {
                    print("RUNTIME_SMOKE: FAIL recording-start")
                    await cancelRuntimeSmokeCaptureIfNeeded()
                    NSApp.terminate(nil)
                    return
                }

                try? await Task.sleep(for: .milliseconds(100))
            }

            print("RUNTIME_SMOKE: FAIL recording-start timeout")
            await cancelRuntimeSmokeCaptureIfNeeded()
            NSApp.terminate(nil)
        }

        private func cancelRuntimeSmokeCaptureIfNeeded() async {
            guard recordingManager.isRecording || recordingManager.isStartingRecording else { return }
            await recordingManager.cancelRecording()
        }
    #endif
}
