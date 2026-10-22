import AVFoundation
import Foundation
@testable import VerbiCore
import XCTest

// MARK: - Mock Audio Engine Protocol

/// Protocolo para abstrair AVAudioEngine para testes determinísticos
protocol MockAudioEngineProtocol {
    var isRunning: Bool { get }
    var mainMixerNode: MockAudioMixerNodeProtocol { get }
    var outputNode: MockAudioOutputNodeProtocol { get }
    var inputNode: MockAudioInputNodeProtocol { get }

    func attach(_ node: MockAudioNodeProtocol)
    func connect(
        _ source: MockAudioNodeProtocol,
        to destination: MockAudioMixerNodeProtocol,
        format: MockAudioFormatProtocol?,
    )
    func prepare() throws
    func start() throws
    func stop()
    func reset()
}

// MARK: - Mock Audio Node Protocol

protocol MockAudioNodeProtocol {
    var auAudioUnit: MockAUAudioUnitProtocol { get }
}

// MARK: - Mock Audio Mixer Node Protocol

protocol MockAudioMixerNodeProtocol: MockAudioNodeProtocol {
    var outputVolume: Float { get set }

    func outputFormat(forBus bus: AVAudioNodeBus) -> MockAudioFormatProtocol
    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: MockAudioFormatProtocol?,
        block: @escaping AVAudioNodeTapBlock,
    )
    func removeTap(onBus bus: AVAudioNodeBus)
}

// MARK: - Mock Audio Source Node Protocol

protocol MockAudioSourceNodeProtocol: MockAudioNodeProtocol {
    init(renderBlock: @escaping AVAudioSourceNodeRenderBlock)
}

// MARK: - Mock Audio Input Node Protocol

protocol MockAudioInputNodeProtocol: MockAudioNodeProtocol {
    func inputFormat(forBus bus: AVAudioNodeBus) -> MockAudioFormatProtocol
}

// MARK: - Mock Audio Output Node Protocol

protocol MockAudioOutputNodeProtocol: MockAudioNodeProtocol {
    func outputFormat(forBus bus: AVAudioNodeBus) -> MockAudioFormatProtocol
}

// MARK: - Mock Audio Format Protocol

protocol MockAudioFormatProtocol {
    var sampleRate: Double { get }
    var channelCount: AVAudioChannelCount { get }
    var commonFormat: AVAudioCommonFormat { get }
    var isInterleaved: Bool { get }
}

// MARK: - Mock AU Audio Unit Protocol

protocol MockAUAudioUnitProtocol {
    var maximumFramesToRender: AVAudioFrameCount { get set }
}

// MARK: - Mock Audio Engine Implementation

/// Mock implementation do AVAudioEngine para testes determinísticos
final class MockAudioEngine: MockAudioEngineProtocol {
    var isRunning: Bool = false
    var mainMixerNode: MockAudioMixerNodeProtocol
    var outputNode: MockAudioOutputNodeProtocol
    var inputNode: MockAudioInputNodeProtocol

    private var attachedNodes: [MockAudioNodeProtocol] = []
    private struct MockConnection {
        let source: MockAudioNodeProtocol
        let destination: MockAudioMixerNodeProtocol
        let format: MockAudioFormatProtocol?
    }

    private var connections: [MockConnection] = []

    // Failure injection for tests
    var shouldFailPrepare = false
    var shouldFailStart = false

    init() {
        mainMixerNode = MockAudioMixerNode()
        outputNode = MockAudioOutputNode()
        inputNode = MockAudioInputNode()
    }

    func attach(_ node: MockAudioNodeProtocol) {
        attachedNodes.append(node)
    }

    func connect(
        _ source: MockAudioNodeProtocol,
        to destination: MockAudioMixerNodeProtocol,
        format: MockAudioFormatProtocol?,
    ) {
        connections.append(MockConnection(source: source, destination: destination, format: format))
    }

    func prepare() throws {
        if shouldFailPrepare {
            throw NSError(
                domain: "MockAudioEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Mock prepare failure"],
            )
        }
    }

    func start() throws {
        if shouldFailStart {
            throw NSError(
                domain: "MockAudioEngine",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Mock start failure"],
            )
        }

        isRunning = true
    }

    func stop() {
        isRunning = false
    }

    func reset() {
        isRunning = false
        attachedNodes.removeAll()
        connections.removeAll()
    }
}

// MARK: - Mock Audio Mixer Node Implementation

final class MockAudioMixerNode: MockAudioMixerNodeProtocol {
    var outputVolume: Float = 1.0
    var auAudioUnit: MockAUAudioUnitProtocol = MockAUAudioUnit()

    private var taps: [AVAudioNodeBus: AVAudioNodeTapBlock] = [:]

    func outputFormat(forBus bus: AVAudioNodeBus) -> MockAudioFormatProtocol {
        MockAudioFormat(sampleRate: 48_000, channelCount: 2, commonFormat: .pcmFormatFloat32, isInterleaved: false)
    }

    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: MockAudioFormatProtocol?,
        block: @escaping AVAudioNodeTapBlock,
    ) {
        taps[bus] = block
    }

    func removeTap(onBus bus: AVAudioNodeBus) {
        taps.removeValue(forKey: bus)
    }

    /// Método para simular chamada de tap em testes
    func simulateTap(onBus bus: AVAudioNodeBus, buffer: AVAudioPCMBuffer, when: AVAudioTime?) {
        if let tapBlock = taps[bus] {
            tapBlock(buffer, when ?? AVAudioTime(hostTime: 0))
        }
    }
}

// MARK: - Mock Audio Source Node Implementation

final class MockAudioSourceNode: MockAudioSourceNodeProtocol {
    var auAudioUnit: MockAUAudioUnitProtocol = MockAUAudioUnit()

    private let renderBlock: AVAudioSourceNodeRenderBlock

    init(renderBlock: @escaping AVAudioSourceNodeRenderBlock) {
        self.renderBlock = renderBlock
    }

    /// Método para simular render callback em testes
    func simulateRender(frameCount: UInt32, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        var isSilence = ObjCBool(false)
        var timeStamp = AudioTimeStamp()
        return renderBlock(&isSilence, &timeStamp, frameCount, audioBufferList)
    }
}

// MARK: - Mock Audio Input Node Implementation

final class MockAudioInputNode: MockAudioInputNodeProtocol {
    var auAudioUnit: MockAUAudioUnitProtocol = MockAUAudioUnit()

    var inputFormatSampleRate: Double = 48_000
    var inputFormatChannels: AVAudioChannelCount = 1
    var inputFormatCommonFormat: AVAudioCommonFormat = .pcmFormatFloat32

    func inputFormat(forBus bus: AVAudioNodeBus) -> MockAudioFormatProtocol {
        MockAudioFormat(
            sampleRate: inputFormatSampleRate,
            channelCount: inputFormatChannels,
            commonFormat: inputFormatCommonFormat,
            isInterleaved: false,
        )
    }
}

// MARK: - Mock Audio Output Node Implementation

final class MockAudioOutputNode: MockAudioOutputNodeProtocol {
    var auAudioUnit: MockAUAudioUnitProtocol = MockAUAudioUnit()

    var outputFormatSampleRate: Double = 48_000
    var outputFormatChannels: AVAudioChannelCount = 2

    func outputFormat(forBus bus: AVAudioNodeBus) -> MockAudioFormatProtocol {
        MockAudioFormat(
            sampleRate: outputFormatSampleRate,
            channelCount: outputFormatChannels,
            commonFormat: .pcmFormatFloat32,
            isInterleaved: false,
        )
    }
}

// MARK: - Mock Audio Format Implementation

struct MockAudioFormat: MockAudioFormatProtocol {
    let sampleRate: Double
    let channelCount: AVAudioChannelCount
    let commonFormat: AVAudioCommonFormat
    let isInterleaved: Bool
}

// MARK: - Mock AU Audio Unit Implementation

final class MockAUAudioUnit: MockAUAudioUnitProtocol {
    var maximumFramesToRender: AVAudioFrameCount = 512
}

// MARK: - Factory para criar mocks

enum MockAudioFactory {
    static func createEngine() -> MockAudioEngine {
        MockAudioEngine()
    }

    static func createMixerNode() -> MockAudioMixerNode {
        MockAudioMixerNode()
    }

    static func createSourceNode(renderBlock: @escaping AVAudioSourceNodeRenderBlock) -> MockAudioSourceNode {
        MockAudioSourceNode(renderBlock: renderBlock)
    }
}

// MARK: - Testes Unitários para MockAudioEngine

final class MockAudioEngineTests: XCTestCase {
    var mockEngine: MockAudioEngine?
    var mockMixer: MockAudioMixerNode?
    var mockSource: MockAudioSourceNode?

    override func setUp() {
        super.setUp()
        mockEngine = MockAudioEngine()
        mockMixer = MockAudioMixerNode()
        mockSource = MockAudioSourceNode { _, _, _, _ in noErr }
    }

    override func tearDown() {
        mockEngine = nil
        mockMixer = nil
        mockSource = nil
        super.tearDown()
    }

    func testInitialState() throws {
        let mockEngine = try XCTUnwrap(mockEngine)
        XCTAssertFalse(mockEngine.isRunning)
        XCTAssertNotNil(mockEngine.mainMixerNode)
        XCTAssertNotNil(mockEngine.outputNode)
        XCTAssertNotNil(mockEngine.inputNode)
    }

    func testAttachNode() throws {
        let mockEngine = try XCTUnwrap(mockEngine)
        let mockSource = try XCTUnwrap(mockSource)
        mockEngine.attach(mockSource)
        // Não há propriedade pública para verificar, mas não deve crash
    }

    func testConnectNodes() throws {
        let mockEngine = try XCTUnwrap(mockEngine)
        let mockSource = try XCTUnwrap(mockSource)
        let mockMixer = try XCTUnwrap(mockMixer)

        let format = MockAudioFormat(
            sampleRate: 48_000,
            channelCount: 2,
            commonFormat: .pcmFormatFloat32,
            isInterleaved: false,
        )
        mockEngine.connect(mockSource, to: mockMixer, format: format)
        // Não há propriedade pública para verificar, mas não deve crash
    }

    func testPrepareSuccess() throws {
        let mockEngine = try XCTUnwrap(mockEngine)
        try mockEngine.prepare()
        // Não deve lançar erro
    }

    func testPrepareFailure() throws {
        let mockEngine = try XCTUnwrap(mockEngine)
        mockEngine.shouldFailPrepare = true

        XCTAssertThrowsError(try mockEngine.prepare()) { error in
            XCTAssertEqual((error as NSError).domain, "MockAudioEngine")
            XCTAssertEqual((error as NSError).code, -1)
        }
    }

    func testStartSuccess() throws {
        let mockEngine = try XCTUnwrap(mockEngine)
        try mockEngine.start()
        XCTAssertTrue(mockEngine.isRunning)
    }

    func testStartFailure() throws {
        let mockEngine = try XCTUnwrap(mockEngine)
        mockEngine.shouldFailStart = true

        XCTAssertThrowsError(try mockEngine.start()) { error in
            XCTAssertEqual((error as NSError).domain, "MockAudioEngine")
            XCTAssertEqual((error as NSError).code, -2)
        }
        XCTAssertFalse(mockEngine.isRunning)
    }

    func testStop() throws {
        let mockEngine = try XCTUnwrap(mockEngine)
        try mockEngine.start()
        XCTAssertTrue(mockEngine.isRunning)

        mockEngine.stop()
        XCTAssertFalse(mockEngine.isRunning)
    }

    func testReset() throws {
        let mockEngine = try XCTUnwrap(mockEngine)
        let mockSource = try XCTUnwrap(mockSource)

        try mockEngine.start()
        mockEngine.attach(mockSource)
        XCTAssertTrue(mockEngine.isRunning)

        mockEngine.reset()
        XCTAssertFalse(mockEngine.isRunning)
    }

    func testMixerNodeOutputFormat() throws {
        let mockMixer = try XCTUnwrap(mockMixer)
        let format = mockMixer.outputFormat(forBus: 0)
        XCTAssertEqual(format.sampleRate, 48_000)
        XCTAssertEqual(format.channelCount, 2)
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(format.isInterleaved)
    }

    func testMixerNodeTapInstallation() throws {
        let mockMixer = try XCTUnwrap(mockMixer)
        var tapCalled = false
        let buffer = try createTestBuffer(frameCount: 1_024)

        mockMixer.installTap(onBus: 0, bufferSize: 2_048, format: nil) { _, _ in
            tapCalled = true
        }

        mockMixer.simulateTap(onBus: 0, buffer: buffer, when: nil)
        XCTAssertTrue(tapCalled)
    }

    func testMixerNodeTapRemoval() throws {
        let mockMixer = try XCTUnwrap(mockMixer)
        var tapCalled = false
        let buffer = try createTestBuffer(frameCount: 1_024)

        mockMixer.installTap(onBus: 0, bufferSize: 2_048, format: nil) { _, _ in
            tapCalled = true
        }

        mockMixer.removeTap(onBus: 0)
        mockMixer.simulateTap(onBus: 0, buffer: buffer, when: nil)
        XCTAssertFalse(tapCalled)
    }

    func testSourceNodeRenderCallback() throws {
        var callbackCalled = false
        let sourceNode = MockAudioSourceNode { _, _, frameCount, audioBufferList in
            callbackCalled = true
            XCTAssertGreaterThan(frameCount, 0)
            XCTAssertNotNil(audioBufferList)
            return noErr
        }

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024) else {
            XCTFail("Failed to create test buffer")
            return
        }
        buffer.frameLength = 1_024

        let status = sourceNode.simulateRender(frameCount: 1_024, audioBufferList: buffer.mutableAudioBufferList)
        XCTAssertEqual(status, noErr)
        XCTAssertTrue(callbackCalled)
    }

    func testInputNodeFormat() {
        let inputNode = MockAudioInputNode()
        let format = inputNode.inputFormat(forBus: 0)

        XCTAssertEqual(format.sampleRate, 48_000)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
    }

    func testOutputNodeFormat() {
        let outputNode = MockAudioOutputNode()
        let format = outputNode.outputFormat(forBus: 0)

        XCTAssertEqual(format.sampleRate, 48_000)
        XCTAssertEqual(format.channelCount, 2)
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
    }

    func testAUAudioUnitMaximumFrames() {
        let auUnit = MockAUAudioUnit()
        XCTAssertEqual(auUnit.maximumFramesToRender, 512)

        auUnit.maximumFramesToRender = 2_048
        XCTAssertEqual(auUnit.maximumFramesToRender, 2_048)
    }

    // MARK: - Helpers

    private func createTestBuffer(frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }
        buffer.frameLength = frameCount
        return buffer
    }
}
