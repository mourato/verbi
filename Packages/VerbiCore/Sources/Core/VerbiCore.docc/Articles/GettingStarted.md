# Getting Started with VerbiCore

This guide helps you integrate and use VerbiCore in your macOS application.

## Installation

VerbiCore is a Swift Package. Add it to your project via Xcode or `Package.swift`:

```swift
.package(path: "Packages/VerbiCore")
```

## Basic Usage

### Initializing the Recording Manager

```swift
import VerbiCore

let recordingManager = RecordingManager.shared
```

### Starting a Recording

```swift
await recordingManager.startRecording()
```

### Stopping and Transcribing

```swift
let url = await recordingManager.stopRecording()
// Proceed to transcription...
```
