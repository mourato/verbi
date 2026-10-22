import Foundation

enum AssistantPayloadLogging {
    private static let payloadDebugUserDefaultsKey = "assistantDebugPayload"
    private static let payloadDebugEnvironmentKey = "MA_ASSISTANT_DEBUG_PAYLOAD"
    private static let payloadPreviewMaxLength = 180

    static var shouldLogPayloadDetails: Bool {
        ProcessInfo.processInfo.environment[payloadDebugEnvironmentKey] == "1"
            || UserDefaults.standard.bool(forKey: payloadDebugUserDefaultsKey)
    }

    static func payloadPreview(_ value: String) -> String {
        let singleLine = value.replacingOccurrences(of: "\n", with: "\\n")
        if singleLine.count <= payloadPreviewMaxLength {
            return singleLine
        }

        return String(singleLine.prefix(payloadPreviewMaxLength)) + "…"
    }
}
