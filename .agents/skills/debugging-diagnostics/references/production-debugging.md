# Production Debugging

## Overview

Debugging in production requires different approaches than development due to limited access and potential impact on users.

## Logging Strategy

### Structured Logging

```swift
import os.log

enum LogCategory {
    case general
    case audio
    case transcription
    case network
    case ui
}

struct AppLogger {
    static let shared = AppLogger()
    
    private let logger: Logger
    
    private init() {
        logger = Logger(subsystem: "com.meeting.assistant", category: "general")
    }
    
    func log(_ message: String, category: LogCategory = .general, level: OSLogType = .default) {
        let categoryString: String
        switch category {
        case .general: categoryString = "General"
        case .audio: categoryString = "Audio"
        case .transcription: categoryString = "Transcription"
        case .network: categoryString = "Network"
        case .ui: categoryString = "UI"
        }
        
        let categoryLogger = Logger(subsystem: "com.meeting.assistant", category: categoryString)
        categoryLogger.log(level: "\(message)")
    }
}
```

### Log Levels

| Level | Type | Use Case |
|-------|------|----------|
| Debug | `.debug` | Development only |
| Info | `.info` | Normal operations |
| Error | `.error` | Recoverable errors |
| Fault | `.fault` | Critical failures |

## Crash Reporting

### Crash Logs Location

```
~/Library/Logs/DiagnosticReports/
```

### Symbolicating Crash Reports

1. Get the .crash file
2. Ensure dSYM is available:
   ```bash
   mdfind "com_meeting_assistant.dSYM"
   ```
3. Use Xcode:
   ```bash
   xcrun atos -arch x86_64 -o Verbi.app/Verbi -l 0x100000000 0x100001234
   ```

## Remote Debugging

### Firebase Crashlytics

```swift
import FirebaseCore
import FirebaseCrashlytics

func configureCrashlytics() {
    FirebaseApp.configure()
    Crashlytics.crashlytics().setCustomValue("value", forKey: "customKey")
    Crashlytics.crashlytics().log("User performed action X")
}
```

## Common Production Issues

### Issue: App Crashes on Launch

**Diagnosis**:
1. Check Crashlytics for stack trace
2. Verify device-specific issues
3. Check for missing entitlements

**Common Causes**:
- Corrupted UserDefaults
- Missing required iOS version check
- Invalid provisioning profile

### Issue: Performance Degradation

**Diagnosis**:
1. Check for memory leaks (Instruments)
2. Look for database growth
3. Monitor network request frequency

**Common Causes**:
- Growing Core Data store
- Unbounded cache growth
- Memory leaks in background tasks

### Issue: Audio Recording Fails

**Diagnosis**:
1. Check microphone permissions
2. Verify audio session configuration
3. Check device memory pressure

## See Also

- [Debugging Tools Guide](debugging-tools-guide.md)
- [Performance Profiling](performance-profiling.md)
