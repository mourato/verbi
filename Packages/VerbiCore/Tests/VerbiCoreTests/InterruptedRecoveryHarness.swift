import Foundation
@testable import VerbiCoreDomain
@testable import VerbiCoreUI
import XCTest

/// Shared fake harness for interrupted-recovery flow tests.
final class InterruptedRecoveryHarness: @unchecked Sendable {
    var activePaths: Set<String> = []
    var busy = false
    var durationProbes: [String] = []
    var readableOverride: [String: Bool] = [:]
    var retrySucceeds = true
    var retryCalls: [String] = []
    var mergeCalls: [[URL]] = []
    var mergeSucceeds = true
    var persistedRequests: [InterruptedRecoveryFlow.StubRequest] = []
    var persistSucceeds = true
    var metadataSnapshots: [[TranscriptionMetadata]]?
    var summaryCounts: [Int] = []
    var stores = InterruptedRecordingRecovery.Stores()
    var now = Date()
}

func makeInterruptedRecoveryFlow(harness: InterruptedRecoveryHarness, storage: MockStorageService) -> InterruptedRecoveryFlow {
    InterruptedRecoveryFlow(io: .init(
        loadStores: { harness.stores },
        saveStores: { harness.stores = $0 },
        listMetadata: {
            if let snapshots = harness.metadataSnapshots, !snapshots.isEmpty {
                harness.metadataSnapshots?.removeFirst()
                return snapshots[0]
            }
            return try await storage.loadAllMetadata()
        },
        loadArtifact: { id in
            try? await storage.loadTranscription(by: id)
        },
        activeAudioPaths: {
            harness.activePaths
        },
        persistStub: { request in
            harness.persistedRequests.append(request)
            guard harness.persistSucceeds else { return nil }
            let meeting = CaptureSession(
                app: request.capturePurpose == .dictation ? .unknown : .manualMeeting,
                capturePurpose: request.capturePurpose,
                title: request.title,
                startTime: request.startTime,
                audioFilePath: request.audioURL.path
            )
            let stub = CaptureArtifact(
                meeting: meeting,
                text: "",
                rawText: "",
                lifecycleState: .failed,
                transcriptionFailureReason: "test-stub"
            )
            try? await storage.saveTranscription(stub)
            return stub.id
        },
        retryArtifact: { transcription in
            let filename = transcription.audioURL?.lastPathComponent ?? ""
            harness.retryCalls.append(filename)
            guard harness.retrySucceeds else { return false }
            let completed = CaptureArtifact(
                id: transcription.id,
                meeting: transcription.meeting,
                text: "done",
                rawText: "done"
            )
            try? await storage.saveTranscription(completed)
            return true
        },
        mergeSplitParts: { parts, output in
            harness.mergeCalls.append(parts)
            guard harness.mergeSucceeds, let first = parts.first else { return nil }
            try? FileManager.default.copyItem(at: first, to: output)
            return output
        },
        audioDuration: { url in
            let filename = url.lastPathComponent
            harness.durationProbes.append(filename)
            if let override = harness.readableOverride[filename] {
                return override ? 60 : nil
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            return size > 0 ? 60 : nil
        },
        isBusy: {
            harness.busy
        },
        notifySummary: { count in
            harness.summaryCounts.append(count)
        },
        now: {
            harness.now
        }
    ))
}
