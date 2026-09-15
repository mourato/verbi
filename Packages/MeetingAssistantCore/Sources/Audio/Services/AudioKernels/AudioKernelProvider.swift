@preconcurrency import AVFoundation
import Foundation
import MeetingAssistantCoreCommon

public struct AudioKernelProvider: Sendable {
    private let voiceActivityFactory: @Sendable () -> any VoiceActivityKernel
    private let energyMeterFactory: @Sendable () -> any EnergyMeterKernel
    private let silenceAnalysisFactory: @Sendable () -> any SilenceAnalysisKernel

    public init(
        voiceActivityFactory: @escaping @Sendable () -> any VoiceActivityKernel = {
            RealtimeVoiceActivityWindowAssembler()
        }
    ) {
        self.init(
            voiceActivityFactory: voiceActivityFactory,
            energyMeterFactory: { SwiftEnergyMeterKernel.shared },
            silenceAnalysisFactory: { SwiftSilenceAnalysisKernel() }
        )
    }

    init(
        voiceActivityFactory: @escaping @Sendable () -> any VoiceActivityKernel,
        energyMeterFactory: @escaping @Sendable () -> any EnergyMeterKernel,
        silenceAnalysisFactory: @escaping @Sendable () -> any SilenceAnalysisKernel
    ) {
        self.voiceActivityFactory = voiceActivityFactory
        self.energyMeterFactory = energyMeterFactory
        self.silenceAnalysisFactory = silenceAnalysisFactory
    }

    public func makeVoiceActivityKernel() -> any VoiceActivityKernel {
        voiceActivityFactory()
    }

    func makeEnergyMeterKernel() -> any EnergyMeterKernel {
        energyMeterFactory()
    }

    func makeSilenceAnalysisKernel() -> any SilenceAnalysisKernel {
        silenceAnalysisFactory()
    }

    public static let live = AudioKernelProvider()
}
