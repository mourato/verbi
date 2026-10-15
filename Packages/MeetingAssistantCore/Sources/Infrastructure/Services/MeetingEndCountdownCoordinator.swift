import Foundation
import MeetingAssistantCoreDomain

/// Coordinates meeting end detection ladder combining audio silence and call control signals.
@MainActor
public final class MeetingEndCountdownCoordinator: ObservableObject {
    public enum EndLadderState: Equatable, Sendable {
        case idle
        case activeCall
        case silenceTracking(elapsedSeconds: TimeInterval)
        case countingDown(remainingSeconds: Int, totalSeconds: Int)
        case silentGrace(remainingSeconds: Int, totalSeconds: Int)
        case completed
        case cancelled
    }

    public enum Constants {
        public static let silenceThresholdBeforeAXCheck: TimeInterval = 10.0
        public static let endedCountdownSeconds: Int = 10
        public static let fallbackGraceCountdownSeconds: Int = 30
        public static let tickInterval: TimeInterval = 1.0
    }

    @Published public private(set) var state: EndLadderState = .idle
    private let callControlProvider: any CallControlSignalProviding
    private var countdownTask: Task<Void, Never>?
    private var silenceTimerTask: Task<Void, Never>?

    private var targetPid: pid_t?
    private var targetApp: MeetingApp?
    private var silenceStartTime: Date?

    public var onCountdownTick: (@MainActor (Int, Int) -> Void)?
    public var onCountdownExpired: (@MainActor () -> Void)?
    public var onContinueRecording: (@MainActor () -> Void)?

    public init(
        callControlProvider: any CallControlSignalProviding = AccessibilityCallControlProvider()
    ) {
        self.callControlProvider = callControlProvider
    }

    deinit {
        countdownTask?.cancel()
        silenceTimerTask?.cancel()
    }

    // MARK: - Monitoring Control

    public func startMonitoring(pid: pid_t, app: MeetingApp) {
        cancel()
        targetPid = pid
        targetApp = app
        state = .activeCall
    }

    public func reportAudioOwnershipActivity(hasAudio: Bool) {
        guard case .activeCall = state, !hasAudio else {
            if hasAudio {
                handleAudioResumed()
            }
            return
        }

        handleAudioSilenceStarted()
    }

    public func handleAudioSilenceStarted() {
        guard state == .activeCall else { return }
        silenceStartTime = Date()
        state = .silenceTracking(elapsedSeconds: 0)

        silenceTimerTask?.cancel()
        silenceTimerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Constants.silenceThresholdBeforeAXCheck))
            guard !Task.isCancelled, let self else { return }
            await checkCallControlAfterSilence()
        }
    }

    public func handleAudioResumed() {
        silenceTimerTask?.cancel()
        silenceTimerTask = nil
        silenceStartTime = nil

        switch state {
        case .silenceTracking, .silentGrace:
            state = .activeCall
        case .countingDown, .idle, .activeCall, .completed, .cancelled:
            break
        }
    }

    public func checkCallControlAfterSilence() async {
        guard let pid = targetPid, let app = targetApp else { return }

        let callState = await callControlProvider.evaluateCallState(for: pid, app: app)
        switch callState {
        case .inCall:
            // Still in call (e.g. muted), return to active call
            state = .activeCall
        case .ended:
            // Explicit end detected -> 10s countdown
            startCountdown(totalSeconds: Constants.endedCountdownSeconds)
        case .inconclusive:
            // Inconclusive -> fallback silent 30s grace without prompt
            startSilentGrace(totalSeconds: Constants.fallbackGraceCountdownSeconds)
        }
    }

    public func triggerDirectEnd() {
        startCountdown(totalSeconds: Constants.endedCountdownSeconds)
    }

    public func startCountdown(totalSeconds: Int) {
        silenceTimerTask?.cancel()
        silenceTimerTask = nil
        countdownTask?.cancel()

        state = .countingDown(remainingSeconds: totalSeconds, totalSeconds: totalSeconds)
        onCountdownTick?(totalSeconds, totalSeconds)

        countdownTask = Task { @MainActor [weak self] in
            var remaining = totalSeconds
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(Constants.tickInterval))
                guard !Task.isCancelled, let self else { return }
                remaining -= 1
                state = .countingDown(remainingSeconds: remaining, totalSeconds: totalSeconds)
                onCountdownTick?(remaining, totalSeconds)
            }

            guard !Task.isCancelled, let self else { return }
            state = .completed
            onCountdownExpired?()
        }
    }

    public func startSilentGrace(totalSeconds: Int = Constants.fallbackGraceCountdownSeconds) {
        silenceTimerTask?.cancel()
        silenceTimerTask = nil
        countdownTask?.cancel()

        state = .silentGrace(remainingSeconds: totalSeconds, totalSeconds: totalSeconds)
        countdownTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Double(totalSeconds)))
            guard !Task.isCancelled, let self else { return }
            state = .completed
            onCountdownExpired?()
        }
    }

    public func continueRecording() {
        countdownTask?.cancel()
        countdownTask = nil
        silenceTimerTask?.cancel()
        silenceTimerTask = nil
        state = .cancelled
        onContinueRecording?()
    }

    public func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        silenceTimerTask?.cancel()
        silenceTimerTask = nil
        state = .idle
        targetPid = nil
        targetApp = nil
        silenceStartTime = nil
    }
}
