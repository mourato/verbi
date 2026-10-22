# Debugging Tools Guide

## Instruments

Instruments is Apple's profiling tool for macOS and iOS applications.

### Getting Started

```bash
# Open Instruments from command line
open -a Instruments

# Or launch with a specific template
xcrun instruments -template "Time Profiler" -target Verbi
```

### Common Templates

| Template | Use Case |
|----------|----------|
| Time Profiler | CPU performance analysis |
| Allocations | Memory allocation tracking |
| Leaks | Memory leak detection |
| Core Animation | UI rendering performance |
| Energy Log | Battery impact analysis |

### Using Time Profiler

1. Select the "Time Profiler" template
2. Choose your target process
3. Click the record button
4. Exercise the functionality you want to profile
5. Stop recording and analyze the call tree

### Key Instruments Shortcuts

- `Cmd+R`: Record
- `Cmd+Space`: Search in trace document
- `Cmd+1/2/3`: Switch between different views

## Xcode Debugger

### Breakpoint Types

**Line Breakpoint**: Click in the gutter next to a line number

**Conditional Breakpoint**:
1. Right-click on breakpoint
2. Edit Breakpoint
3. Add condition (e.g., `index == 5`)

**Exception Breakpoint**:
1. Debug > Breakpoints > Create Exception Breakpoint
2. Catch Objective-C and C++ exceptions

**Symbolic Breakpoint**:
1. Add symbolic breakpoint
2. Symbol: `[ClassName methodName:]`

### LLDB Commands

```lldb
# Print variable
po myVariable
p myVariable

# Print expression
expr myVariable = newValue

# Call method
expr [myObject doSomething]

# Backtrace
bt

# Thread backtrace
thread backtrace

# List breakpoints
br list

# Add breakpoint by location
breakpoint set --file MyFile.swift --line 42

# Watch variable
watchpoint set variable myVariable

# Step instructions
thread step-inst
thread step-inst-over
thread step-out
```

### Quick Debugging Tricks

```lldb
# Print all local variables
frame variable

# Print view hierarchy
expr -l ObjC -O -- [[UIApplication sharedApplication] keyWindow]

# Change theme during debugging
settings set target.xcode-theme-name 'Light'
```

## Console.app

### Filtering Logs

Use the search field to filter by:

```
# Filter by process
process == "Verbi"

# Filter by subsystem
subsystem == "com.meeting.assistant"

# Filter by level
eventMessage contains "error"
```

### Create Custom Subsystem

```swift
import os.log

let subsystem = "com.meeting.assistant"
let logger = Logger(subsystem: subsystem, category: "audio")

logger.log("Recording started")
logger.error("Failed to start recording: \(error.localizedDescription)")
```

### Export Logs

1. Select logs in Console.app
2. File > Export
3. Choose .log or .asl format

## SwiftUI Debugging

### View Debugging

```swift
// Add to view hierarchy
@Environment(\.redactedReasons) var redactedReasons

// Debug print in SwiftUI
struct ContentView: View {
    var body: some View {
        Text("Hello")
            .onAppear {
                print("Appeared")
            }
    }
}

// Use #fileID and #line for better debugging
.log("File: \(#fileID), Line: #\(line)")
```

### Property Wrapper Debugging

```swift
// Debug @State changes
class Debugger: ObservableObject {
    @Published var value: Int = 0 {
        willSet {
            print("Will change from \(value) to \(newValue)")
        }
    }
}
```

## Network Debugging

### URLSession Debugging

```swift
// Enable URLSession debug logging
URLSession.shared.configuration.httpAdditionalHeaders = [
    "X-Debug-Token": "true"
]

// Use a logging protocol
class LoggingURLProtocol: URLProtocol {
    override func startLoading() {
        // Log request
        print("Request: \(self.request.url?.absoluteString ?? "")")
        
        // Forward to next handler
        // ...
    }
}
```

## See Also

- [Performance Profiling](performance-profiling.md)
- [Production Debugging](production-debugging.md)
