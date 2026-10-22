import Foundation
import VerbiCoreAI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

// MARK: - Summary Export

extension RecordingManager {
    /// Export summary to configured folder with safety checks.
    func exportSummary(transcription: CaptureArtifact) async {
        let helper = SummaryExportHelper()
        await helper.exportAutomatically(transcription: transcription)
    }
}
