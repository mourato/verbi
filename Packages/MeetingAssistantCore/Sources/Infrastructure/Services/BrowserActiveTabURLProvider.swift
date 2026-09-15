import Foundation
import MeetingAssistantCoreCommon
import os.log

public protocol BrowserActiveTabURLProviding {
    func activeTabURL() -> URL?
}

public final class BrowserActiveTabURLProvider: BrowserActiveTabURLProviding {
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "BrowserActiveTabURLProvider")
    private let script: NSAppleScript
    private static let automationPermissionDeniedErrorCode = -1743

    public init?(applicationName: String, scriptTemplate: String) {
        let source = String(format: scriptTemplate, applicationName)
        guard let script = NSAppleScript(source: source) else {
            return nil
        }
        self.script = script
    }

    public func activeTabURL() -> URL? {
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int
            let errorMessage = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown"

            if errorNumber == Self.automationPermissionDeniedErrorCode {
                logger.warning("AppleScript automation permission denied: \(errorMessage, privacy: .public)")
            } else {
                logger.debug("AppleScript error [\(errorNumber ?? 0)]: \(errorMessage, privacy: .public)")
            }
            return nil
        }

        let urlString = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let urlString, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }
}

public enum BrowserScriptTemplates {
    public static let safariFrontDocument = "tell application \"%@\" to get URL of front document"
    public static let safariCurrentTab = "tell application \"%@\" to get URL of current tab of front window"
    public static let chromium = "tell application \"%@\" to get URL of active tab of front window"
}

public final class FallbackBrowserActiveTabURLProvider: BrowserActiveTabURLProviding {
    private let providers: [BrowserActiveTabURLProviding]

    public init(providers: [BrowserActiveTabURLProviding]) {
        self.providers = providers
    }

    public func activeTabURL() -> URL? {
        for provider in providers {
            if let url = provider.activeTabURL() {
                return url
            }
        }

        return nil
    }
}
