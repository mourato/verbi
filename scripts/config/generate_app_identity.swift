#!/usr/bin/swift
import Foundation

let invocationURL = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
let root = invocationURL.standardizedFileURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let manifestURL = root.appendingPathComponent("Config/AppIdentity.plist")
let data = try Data(contentsOf: manifestURL)
guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
    fatalError("AppIdentity.plist must contain a dictionary")
}

func section(_ name: String) -> [String: Any] {
    guard let result = plist[name] as? [String: Any] else {
        fatalError("Missing identity section: \(name)")
    }
    return result
}

func value(_ sectionName: String, _ key: String) -> String {
    guard let result = section(sectionName)[key] as? String else {
        fatalError("Missing identity value: \(sectionName).\(key)")
    }
    return result
}

func stringArray(_ sectionName: String, _ key: String) -> [String] {
    guard let result = section(sectionName)[key] as? [String], !result.isEmpty else {
        fatalError("Missing identity string array: \(sectionName).\(key)")
    }
    return result
}

func swiftStringArray(_ values: [String]) -> String {
    "[" + values.map { String(reflecting: $0) }.joined(separator: ", ") + "]"
}

let check = CommandLine.arguments.dropFirst().contains("--check")
let header = "// GENERATED FILE — DO NOT EDIT. Source: Config/AppIdentity.plist.\n"
func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

let legacyAppSupportDirectories = stringArray("migration", "legacyAppSupportDirectories")
let legacyLogDirectories = stringArray("migration", "legacyLogDirectories")
let legacyKeychainServices = stringArray("migration", "legacyKeychainServices")
let legacyUserDefaultsDomains = stringArray("migration", "legacyUserDefaultsDomains")

let xcconfig = """
// GENERATED FILE — DO NOT EDIT. Source: Config/AppIdentity.plist.
APP_DISPLAY_NAME = \(value("product", "displayName"))
APP_PRODUCT_NAME = \(value("product", "productName"))
APP_BUNDLE_ID = \(value("technical", "bundleIdentifier"))

XPC_SERVICE_BUNDLE_ID = \(value("technical", "xpcServiceBundleIdentifier"))
XPC_PRODUCT_NAME = \(value("technical", "xpcProductName"))

APP_SUPPORT_DIR_NAME = \(value("persistence", "appSupportDirectory"))
APP_LOG_DIR_NAME = \(value("persistence", "logDirectory"))
KEYCHAIN_SERVICE_ID = \(value("technical", "keychainService"))
APP_LOG_SUBSYSTEM = \(value("technical", "logSubsystem"))
HOTKEY_SIGNATURE_SEED = \(value("persistence", "hotkeySignatureSeed"))

"""

let swift = """
\(header)import Foundation

public enum AppIdentityValues {
    public static let displayName = \(String(reflecting: value("product", "displayName")))
    public static let bundleIdentifier = \(String(reflecting: value("technical", "bundleIdentifier")))
    public static let xpcServiceName = \(String(reflecting: value("technical", "xpcServiceBundleIdentifier")))
    public static let logSubsystem = \(String(reflecting: value("technical", "logSubsystem")))
    public static let appSupportDirectoryName = \(String(reflecting: value("persistence", "appSupportDirectory")))
    public static let logDirectoryName = \(String(reflecting: value("persistence", "logDirectory")))
    public static let keychainServiceIdentifier = \(String(reflecting: value("technical", "keychainService")))
    public static let hotkeySignatureSeed = \(String(reflecting: value("persistence", "hotkeySignatureSeed")))
    public static let userDefaultsDomainMigrationFlag = \(String(reflecting: value("persistence", "userDefaultsMigrationFlag")))
    public static let legacyAppSupportDirectoryNames = \(swiftStringArray(legacyAppSupportDirectories))
    public static let legacyLogDirectoryNames = \(swiftStringArray(legacyLogDirectories))
    public static let legacyKeychainServiceIdentifiers = \(swiftStringArray(legacyKeychainServices))
    public static let legacyUserDefaultsDomains = \(swiftStringArray(legacyUserDefaultsDomains))
    public static let settingsToolbarIdentifier = \(String(reflecting: value("internal", "settingsToolbarIdentifier")))
    public static let settingsWindowAutosaveName = \(String(reflecting: value("internal", "settingsWindowAutosaveName")))
}

"""

let shell = """
#!/bin/bash
# GENERATED FILE — DO NOT EDIT. Source: Config/AppIdentity.plist.
APP_SCHEME=\(shellQuote(value("internal", "appScheme")))
APP_PRODUCT_NAME=\(shellQuote(value("product", "productName")))
XCODEPROJ_NAME=\(shellQuote(value("internal", "xcodeprojName")))
XPC_TARGET_NAME=\(shellQuote(value("internal", "xpcTargetName")))
XPC_PRODUCT_NAME=\(shellQuote(value("technical", "xpcProductName")))

"""

let outputs: [(String, String)] = [
    ("Config/Branding.xcconfig", xcconfig),
    ("Packages/MeetingAssistantCore/Sources/Common/Config/AppIdentityValues.generated.swift", swift),
    ("scripts/config/app_identity.sh", shell),
]
var stale = false
for (path, content) in outputs {
    let url = root.appendingPathComponent(path)
    if check {
        if (try? String(contentsOf: url, encoding: .utf8)) != content {
            stale = true
            print("stale: \(path)")
        }
    } else {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

if stale {
    exit(1)
}
