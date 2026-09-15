import Foundation
import MeetingAssistantCoreCommon

public enum AssistantBashScriptRunnerError: LocalizedError, Equatable {
    case executionTimeout
    case launchFailed

    public var errorDescription: String? {
        switch self {
        case .executionTimeout:
            "settings.assistant.integrations.script.error.timeout".localized
        case .launchFailed:
            "settings.assistant.integrations.script.error.launch".localized
        }
    }
}

public actor AssistantBashScriptRunner {
    public init() {}

    public func run(
        script: String,
        input: String,
        timeoutSeconds: UInt64 = 15
    ) async throws -> String? {
        let trimmedScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedScript.isEmpty else {
            return input
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", trimmedScript]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe

        let terminated = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    process.terminationHandler = { _ in
                        continuation.resume(returning: ())
                    }

                    do {
                        try process.run()
                        if let data = input.data(using: .utf8) {
                            stdinPipe.fileHandleForWriting.write(data)
                        }
                        try? stdinPipe.fileHandleForWriting.close()
                    } catch {
                        continuation.resume(returning: ())
                    }
                }
                return process.isRunning == false
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        if !terminated {
            if process.isRunning {
                process.terminate()
            }
            throw AssistantBashScriptRunnerError.executionTimeout
        }

        guard process.terminationStatus == 0 else {
            throw AssistantBashScriptRunnerError.launchFailed
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? nil : output
    }
}
