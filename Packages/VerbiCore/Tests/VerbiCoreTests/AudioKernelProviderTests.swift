@preconcurrency import AVFoundation
@testable import VerbiCoreAudio
import XCTest

final class AudioKernelProviderTests: XCTestCase {
    func testInitWithCustomFactories_UsesProvidedVoiceKernel() {
        let voiceKernel = StubVoiceActivityKernel()
        let provider = AudioKernelProvider(voiceActivityFactory: { voiceKernel })

        let produced = provider.makeVoiceActivityKernel()

        XCTAssertTrue((produced as AnyObject) === (voiceKernel as AnyObject))
    }

    func testLive_UsesSwiftVoiceActivityKernel() {
        let provider = AudioKernelProvider.live
        let kernel = provider.makeVoiceActivityKernel()

        XCTAssertTrue(kernel is RealtimeVoiceActivityWindowAssembler)
    }
}

private actor StubVoiceActivityKernel: VoiceActivityKernel {
    func setAdaptiveQualityMode(_ mode: RealtimeVoiceActivityWindowAssembler.AdaptiveQualityMode) async {}

    func append(buffer _: AVAudioPCMBuffer) async throws -> [RealtimeVoiceActivityWindowAssembler.Window] {
        []
    }

    func finish() async throws -> [RealtimeVoiceActivityWindowAssembler.Window] {
        []
    }
}
