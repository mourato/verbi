import Foundation
import VerbiCoreAI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

extension RecordingManager {
    func exportSummary(transcription: CaptureArtifact) async {
        let helper = SummaryExportHelper()
        await helper.exportAutomatically(transcription: transcription)
    }
}
