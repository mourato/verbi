#!/usr/bin/env swift
//
// Generate Verbi's original MIT-licensed recording sound feedback cues (.m4a).
//
// All eight cues (four paired start/stop themes: Light, Creamy, Thocky, Petal)
// are synthesized deterministically from basic mathematical waveforms and written
// directly to 48 kHz stereo AAC (.m4a) via AVFoundation. No third-party audio
// recordings, external assets, or subprocesses are used.
//
// License: MIT (Copyright Verbi Team, same as repository LICENSE).
// Usage: swift scripts/generate-sound-feedback-cues.swift

import AVFoundation
import Foundation

private struct HarmonicSpec {
    let ratio: Double
    let amplitude: Double
    let decayScale: Double
}

private struct NoteSpec {
    let start: Double
    let frequency: Double
    let attack: Double
    let decay: Double
    let amplitude: Double
    let pan: Double
    let harmonics: [HarmonicSpec]
}

private struct ThockSpec {
    let duration: Double
    let baseStartHz: Double
    let baseEndHz: Double
    let bodyHz: Double
    let woodHz: Double
    let woodAmplitude: Double
    let doubleTap: Bool
}

private struct TapSpec {
    let start: Double
    let gain: Double
    let pitch: Double
}

private struct StereoAudio {
    var left: [Float]
    var right: [Float]
}

private enum SoundCueGenerator {
    static let sampleRate: Double = 48000
    static let targetPeak: Double = 0.42

    static var outputDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packages/VerbiCore/Sources/Audio/Resources/Sounds", isDirectory: true)
    }

    static func run() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let lightHarmonics = [
            HarmonicSpec(ratio: 1.0, amplitude: 1.0, decayScale: 1.0),
            HarmonicSpec(ratio: 2.0, amplitude: 0.14, decayScale: 0.45),
            HarmonicSpec(ratio: 3.0, amplitude: 0.03, decayScale: 0.25)
        ]
        let creamyHarmonics = [
            HarmonicSpec(ratio: 1.0, amplitude: 1.0, decayScale: 1.0),
            HarmonicSpec(ratio: 2.0, amplitude: 0.20, decayScale: 0.60),
            HarmonicSpec(ratio: 3.0, amplitude: 0.04, decayScale: 0.30)
        ]
        let petalHarmonics = [
            HarmonicSpec(ratio: 1.0, amplitude: 1.0, decayScale: 1.0),
            HarmonicSpec(ratio: 2.0, amplitude: 0.18, decayScale: 0.52),
            HarmonicSpec(ratio: 2.76, amplitude: 0.05, decayScale: 0.28)
        ]

        let cues: [(String, StereoAudio)] = [
            ("light_start", renderNotes(duration: 0.27, notes: [
                NoteSpec(start: 0.004, frequency: 880.0, attack: 0.005, decay: 0.070, amplitude: 0.85, pan: -0.08, harmonics: lightHarmonics),
                NoteSpec(start: 0.052, frequency: 1318.51, attack: 0.005, decay: 0.095, amplitude: 1.0, pan: 0.08, harmonics: lightHarmonics)
            ])),
            ("light_stop", renderNotes(duration: 0.27, notes: [
                NoteSpec(start: 0.004, frequency: 1174.66, attack: 0.005, decay: 0.068, amplitude: 0.85, pan: 0.08, harmonics: lightHarmonics),
                NoteSpec(start: 0.054, frequency: 783.99, attack: 0.006, decay: 0.095, amplitude: 1.0, pan: -0.08, harmonics: lightHarmonics)
            ])),
            ("creamy_start", renderNotes(duration: 0.44, notes: [
                NoteSpec(start: 0.005, frequency: 349.23, attack: 0.014, decay: 0.150, amplitude: 0.85, pan: -0.10, harmonics: creamyHarmonics),
                NoteSpec(start: 0.034, frequency: 440.00, attack: 0.014, decay: 0.160, amplitude: 0.80, pan: 0.00, harmonics: creamyHarmonics),
                NoteSpec(start: 0.064, frequency: 523.25, attack: 0.014, decay: 0.175, amplitude: 0.90, pan: 0.10, harmonics: creamyHarmonics)
            ])),
            ("creamy_stop", renderNotes(duration: 0.44, notes: [
                NoteSpec(start: 0.005, frequency: 523.25, attack: 0.014, decay: 0.140, amplitude: 0.80, pan: 0.10, harmonics: creamyHarmonics),
                NoteSpec(start: 0.036, frequency: 440.00, attack: 0.014, decay: 0.150, amplitude: 0.82, pan: 0.00, harmonics: creamyHarmonics),
                NoteSpec(start: 0.068, frequency: 349.23, attack: 0.016, decay: 0.175, amplitude: 0.95, pan: -0.10, harmonics: creamyHarmonics)
            ])),
            ("thocky_start", renderThock(ThockSpec(
                duration: 0.22, baseStartHz: 310, baseEndHz: 155, bodyHz: 440, woodHz: 860, woodAmplitude: 0.34, doubleTap: true
            ))),
            ("thocky_stop", renderThock(ThockSpec(
                duration: 0.22, baseStartHz: 245, baseEndHz: 122, bodyHz: 340, woodHz: 640, woodAmplitude: 0.26, doubleTap: false
            ))),
            ("petal_start", renderNotes(duration: 0.48, notes: [
                NoteSpec(start: 0.005, frequency: 659.25, attack: 0.007, decay: 0.170, amplitude: 0.85, pan: -0.12, harmonics: petalHarmonics),
                NoteSpec(start: 0.060, frequency: 987.77, attack: 0.007, decay: 0.210, amplitude: 1.00, pan: 0.12, harmonics: petalHarmonics)
            ])),
            ("petal_stop", renderNotes(duration: 0.48, notes: [
                NoteSpec(start: 0.005, frequency: 987.77, attack: 0.007, decay: 0.155, amplitude: 0.82, pan: 0.12, harmonics: petalHarmonics),
                NoteSpec(start: 0.062, frequency: 659.25, attack: 0.008, decay: 0.210, amplitude: 1.00, pan: -0.12, harmonics: petalHarmonics)
            ]))
        ]

        for (name, audio) in cues {
            let url = try writeM4A(named: name, audio: audio)
            let size = try (FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            print("Generated \(url.lastPathComponent) (\(size) bytes)")
        }
    }

    private static func envelope(time: Double, start: Double, attack: Double, decay: Double) -> Double {
        let elapsed = time - start
        guard elapsed >= 0 else { return 0 }
        if elapsed < attack {
            return 0.5 * (1.0 - cos(.pi * elapsed / attack))
        }
        return exp(-(elapsed - attack) / decay)
    }

    private static func tailFade(time: Double, duration: Double, length: Double = 0.025) -> Double {
        let remaining = duration - time
        guard remaining > 0 else { return 0 }
        guard remaining < length else { return 1 }
        return 0.5 * (1.0 - cos(.pi * remaining / length))
    }

    private static func noteSample(_ note: NoteSpec, at time: Double) -> (left: Double, right: Double) {
        let elapsed = time - note.start
        guard elapsed >= 0 else { return (0, 0) }
        var sum = 0.0
        for harmonic in note.harmonics {
            let env = envelope(time: time, start: note.start, attack: note.attack, decay: note.decay * harmonic.decayScale)
            sum += harmonic.amplitude * env * sin(2.0 * .pi * note.frequency * harmonic.ratio * elapsed)
        }
        let value = sum * note.amplitude
        return (value * sqrt(0.5 * (1.0 - note.pan)), value * sqrt(0.5 * (1.0 + note.pan)))
    }

    private static func renderNotes(duration: Double, notes: [NoteSpec]) -> StereoAudio {
        let count = Int(duration * sampleRate)
        var left = [Double](repeating: 0, count: count)
        var right = [Double](repeating: 0, count: count)

        for index in 0 ..< count {
            let time = Double(index) / sampleRate
            let fade = tailFade(time: time, duration: duration)
            var leftSum = 0.0
            var rightSum = 0.0
            for note in notes {
                let sample = noteSample(note, at: time)
                leftSum += sample.left
                rightSum += sample.right
            }
            left[index] = leftSum * fade
            right[index] = rightSum * fade
        }
        return normalize(left: left, right: right, peakTarget: targetPeak)
    }

    private static func renderThock(_ spec: ThockSpec) -> StereoAudio {
        let count = Int(spec.duration * sampleRate)
        var left = [Double](repeating: 0, count: count)
        var right = [Double](repeating: 0, count: count)
        let taps: [TapSpec] = spec.doubleTap
            ? [TapSpec(start: 0.004, gain: 1.0, pitch: 1.0), TapSpec(start: 0.056, gain: 0.58, pitch: 1.18)]
            : [TapSpec(start: 0.004, gain: 1.0, pitch: 1.0)]

        for tap in taps {
            accumulateTap(tap, spec: spec, left: &left, right: &right)
        }
        for index in 0 ..< count {
            let fade = tailFade(time: Double(index) / sampleRate, duration: spec.duration, length: 0.020)
            left[index] *= fade
            right[index] *= fade
        }
        return normalize(left: left, right: right, peakTarget: targetPeak * 0.95)
    }

    private static func accumulateTap(
        _ tap: TapSpec,
        spec: ThockSpec,
        left: inout [Double],
        right: inout [Double]
    ) {
        var phase = 0.0
        for index in left.indices {
            let time = Double(index) / sampleRate
            let elapsed = time - tap.start
            guard elapsed >= 0 else { continue }

            let freq = tap.pitch * (spec.baseEndHz + (spec.baseStartHz - spec.baseEndHz) * exp(-elapsed / 0.014))
            phase += 2.0 * .pi * freq / sampleRate

            let thud = sin(phase) * envelope(time: time, start: tap.start, attack: 0.0018, decay: 0.036)
            let body = 0.55 * sin(2.0 * .pi * spec.bodyHz * tap.pitch * elapsed)
                * envelope(time: time, start: tap.start, attack: 0.0015, decay: 0.024)
            let woodWave = sin(2.0 * .pi * spec.woodHz * tap.pitch * elapsed)
                + 0.45 * sin(2.0 * .pi * spec.woodHz * 1.48 * tap.pitch * elapsed)
            let wood = spec.woodAmplitude * woodWave
                * envelope(time: time, start: tap.start, attack: 0.0009, decay: 0.011)

            let value = (thud + body + wood) * tap.gain
            let spread = 0.06 * wood * tap.gain
            left[index] += value + spread
            right[index] += value - spread
        }
    }

    private static func normalize(left: [Double], right: [Double], peakTarget: Double) -> StereoAudio {
        let peak = max(left.map(abs).max() ?? 0, right.map(abs).max() ?? 0)
        let scale = peak > 1e-9 ? peakTarget / peak : 1.0
        return StereoAudio(
            left: left.map { Float($0 * scale) },
            right: right.map { Float($0 * scale) }
        )
    }

    private static func writeM4A(named name: String, audio: StereoAudio) throws -> URL {
        let outputURL = outputDirectory.appendingPathComponent("\(name).m4a")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let frameCount = AVAudioFrameCount(audio.left.count)
        guard let pcmFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: 2,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData
        else {
            throw NSError(domain: "SoundCueGenerator", code: 1)
        }

        buffer.frameLength = frameCount
        audio.left.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                channelData[0].update(from: base, count: audio.left.count)
            }
        }
        audio.right.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                channelData[1].update(from: base, count: audio.right.count)
            }
        }

        let tempCAF = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name).caf")
        defer { try? FileManager.default.removeItem(at: tempCAF) }

        let pcmSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let tempFile = try AVAudioFile(
            forWriting: tempCAF,
            settings: pcmSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try tempFile.write(from: buffer)

        try exportCompactM4A(from: tempCAF, to: outputURL)
        return outputURL
    }

    private static func exportCompactM4A(from sourceURL: URL, to destinationURL: URL) throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "SoundCueGenerator", code: 2)
        }
        exporter.outputURL = destinationURL
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = true

        let semaphore = DispatchSemaphore(value: 0)
        exporter.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        if exporter.status != .completed {
            throw exporter.error ?? NSError(domain: "SoundCueGenerator", code: 3)
        }
    }
}

try SoundCueGenerator.run()
