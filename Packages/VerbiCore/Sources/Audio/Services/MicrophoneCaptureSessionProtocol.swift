@preconcurrency import AVFoundation
import Foundation

typealias MicrophoneCaptureSessionFactory = (
    @escaping @Sendable (AVAudioPCMBuffer) -> Void,
    @escaping @Sendable (Error) -> Void
) throws -> any MicrophoneCaptureSessionProtocol

protocol MicrophoneCaptureSessionProtocol: Sendable {
    var format: AVAudioFormat { get }
    func start(deviceUID: String?) async throws
    func stop() async
}

func makeDefaultMicrophoneCaptureSession(
    onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
    onFailure: @escaping @Sendable (Error) -> Void
) throws -> any MicrophoneCaptureSessionProtocol {
    try MicrophoneCaptureSession(onBuffer: onBuffer, onFailure: onFailure)
}
