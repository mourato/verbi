import AppKit
import Foundation
import MeetingAssistantCoreCommon

public enum AssistantIntegrationDispatchResult: Equatable {
    case openedDeepLink
    case openedWithClipboardFallback
}

public enum AssistantIntegrationDispatchError: Error, Equatable {
    case invalidDeepLink
    case openFailed
}

public enum AssistantIntegrationDeepLinkValidation: Equatable {
    case valid
    case invalid
}

@MainActor
public protocol AssistantDeepLinkDispatching {
    func validateDeepLink(_ value: String) -> AssistantIntegrationDeepLinkValidation
    func dispatch(command: String, baseDeepLink: String) throws -> AssistantIntegrationDispatchResult
}

@MainActor
public final class AssistantRaycastIntegrationService: AssistantDeepLinkDispatching {
    private enum Constants {
        static let dispatchQueryNames = ["fallbackText", "text", "query", "prompt"]
        static let supportedHosts: Set<String> = ["extensions", "script-commands", "ai-commands", "confetti"]
    }

    private let openURL: (URL) -> Bool
    private let maxDeepLinkLength: Int

    public init(
        workspace: NSWorkspace = .shared,
        pasteboard _: NSPasteboard = .general,
        maxDeepLinkLength: Int = 3800
    ) {
        openURL = { url in workspace.open(url) }
        self.maxDeepLinkLength = maxDeepLinkLength
    }

    public init(
        openURL: @escaping (URL) -> Bool,
        copyToClipboard _: @escaping (String) -> Void,
        maxDeepLinkLength: Int = 3800
    ) {
        self.openURL = openURL
        self.maxDeepLinkLength = maxDeepLinkLength
    }

    public func validateDeepLink(_ value: String) -> AssistantIntegrationDeepLinkValidation {
        let deeplink = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deeplink.isEmpty, let components = URLComponents(string: deeplink) else {
            AppLogger.warning(
                "Raycast deeplink validation failed: empty or malformed",
                category: .assistant,
                extra: ["length": deeplink.count]
            )
            return .invalid
        }

        guard components.scheme?.lowercased() == "raycast" else {
            AppLogger.warning(
                "Raycast deeplink validation failed: invalid scheme",
                category: .assistant,
                extra: ["scheme": components.scheme ?? "nil"]
            )
            return .invalid
        }

        guard isSupportedRaycastCommand(components) else {
            AppLogger.warning(
                "Raycast deeplink validation failed: unsupported host/path format",
                category: .assistant,
                extra: [
                    "host": components.host ?? "nil",
                    "path": components.path
                ]
            )
            return .invalid
        }

        AppLogger.debug(
            "Raycast deeplink validation succeeded",
            category: .assistant,
            extra: ["host": components.host ?? "nil"]
        )
        return .valid
    }

    public func dispatch(command: String, baseDeepLink: String) throws -> AssistantIntegrationDispatchResult {
        AppLogger.info(
            "Dispatching Assistant command to Raycast",
            category: .assistant,
            extra: [
                "commandLength": command.count,
                "deepLinkLength": baseDeepLink.count
            ]
        )

        guard var components = makeComponents(from: baseDeepLink) else {
            AppLogger.error(
                "Raycast dispatch failed: invalid deeplink",
                category: .assistant,
                extra: ["deepLinkLength": baseDeepLink.count]
            )
            throw AssistantIntegrationDispatchError.invalidDeepLink
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { Constants.dispatchQueryNames.contains($0.name) }
        queryItems.append(contentsOf: Constants.dispatchQueryNames.map { key in
            URLQueryItem(name: key, value: command)
        })
        components.queryItems = queryItems

        guard let fullURL = components.url else {
            throw AssistantIntegrationDispatchError.invalidDeepLink
        }

        if AssistantPayloadLogging.shouldLogPayloadDetails {
            AppLogger.debug(
                "Raycast dispatch composed URL",
                category: .assistant,
                extra: [
                    "baseDeepLink": baseDeepLink,
                    "fullURL": fullURL.absoluteString,
                    "payloadPreview": AssistantPayloadLogging.payloadPreview(command),
                    "payloadByQuery": payloadSummary(from: components)
                ]
            )
        }

        if fullURL.absoluteString.count > maxDeepLinkLength {
            AppLogger.warning(
                "Raycast dispatch exceeds recommended deeplink length; opening deeplink with inline payload",
                category: .assistant,
                extra: [
                    "fullURLLength": fullURL.absoluteString.count,
                    "maxLength": maxDeepLinkLength
                ]
            )
        }

        guard openURL(fullURL) else {
            AppLogger.error("Raycast dispatch failed to open deeplink", category: .assistant)
            throw AssistantIntegrationDispatchError.openFailed
        }

        AppLogger.info("Raycast deeplink opened successfully", category: .assistant)
        return .openedDeepLink
    }

    private func makeComponents(from deepLink: String) -> URLComponents? {
        let trimmed = deepLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let components = URLComponents(string: trimmed) else {
            return nil
        }

        guard components.scheme?.lowercased() == "raycast" else {
            return nil
        }

        guard isSupportedRaycastCommand(components) else {
            return nil
        }

        return components
    }

    private func isSupportedRaycastCommand(_ components: URLComponents) -> Bool {
        guard let host = components.host?.lowercased(), Constants.supportedHosts.contains(host) else {
            return false
        }

        let pathSegments = components.path
            .split(separator: "/")
            .map(String.init)

        switch host {
        case "confetti":
            return pathSegments.isEmpty
        case "ai-commands", "script-commands":
            return pathSegments.count >= 1
        case "extensions":
            return pathSegments.count >= 3
        default:
            return false
        }
    }

    private func payloadSummary(from components: URLComponents) -> String {
        let values = (components.queryItems ?? [])
            .filter { Constants.dispatchQueryNames.contains($0.name) }
            .map { item in
                let value = item.value ?? ""
                return "\(item.name)=\(AssistantPayloadLogging.payloadPreview(value))"
            }

        if values.isEmpty {
            return "none"
        }

        return values.joined(separator: " | ")
    }
}
