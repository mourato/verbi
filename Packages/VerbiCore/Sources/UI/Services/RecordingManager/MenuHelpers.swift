import AVFoundation
import Combine
import Foundation
import os.log
import UserNotifications
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

// MARK: - Menu Helpers

public extension RecordingManager {
    var dictationMenuKey: String {
        (isRecording && currentCapturePurpose == .dictation) ? "menubar.stop_dictation" : "menubar.dictate"
    }

    var meetingMenuKey: String {
        (isRecording && currentCapturePurpose == .meeting) ? "menubar.stop_recording" : "menubar.record_meeting"
    }
}
