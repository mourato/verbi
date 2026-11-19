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

func developmentValue(_ key: String) -> String {
    value("development", key)
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
APP_DISPLAY_NAME[config=Debug] = \(developmentValue("displayName"))
APP_PRODUCT_NAME = \(value("product", "productName"))
APP_BUNDLE_ID = \(value("technical", "bundleIdentifier"))
APP_BUNDLE_ID[config=Debug] = \(developmentValue("bundleIdentifier"))
APP_URL_SCHEME = \(value("technical", "urlScheme"))
APP_URL_SCHEME[config=Debug] = \(developmentValue("urlScheme"))
APP_URL_NAME = \(value("technical", "urlName"))
APP_URL_NAME[config=Debug] = \(developmentValue("urlName"))

APP_SUPPORT_DIR_NAME = \(value("persistence", "appSupportDirectory"))
APP_SUPPORT_DIR_NAME[config=Debug] = \(developmentValue("appSupportDirectory"))
APP_LOG_DIR_NAME = \(value("persistence", "logDirectory"))
APP_LOG_DIR_NAME[config=Debug] = \(developmentValue("logDirectory"))
KEYCHAIN_SERVICE_ID = \(value("technical", "keychainService"))
KEYCHAIN_SERVICE_ID[config=Debug] = \(developmentValue("keychainService"))
APP_LOG_SUBSYSTEM = \(value("technical", "logSubsystem"))
APP_LOG_SUBSYSTEM[config=Debug] = \(developmentValue("logSubsystem"))
HOTKEY_SIGNATURE_SEED = \(value("persistence", "hotkeySignatureSeed"))

"""

/// One build configuration's constants. Release keeps the installed identity.
/// Debug gets its own identity and an empty legacy list, so it never migrates
/// or reads data that belongs to the installed app.
struct IdentityConstants {
    var displayName: String
    var bundleIdentifier: String
    var logSubsystem: String
    var appSupportDirectory: String
    var logDirectory: String
    var keychainService: String
    var urlScheme: String
    var settingsWindowAutosaveName: String
    var legacyAppSupportDirectories: [String]
    var legacyLogDirectories: [String]
    var legacyKeychainServices: [String]
    var legacyUserDefaultsDomains: [String]
}

func swiftConstants(_ identity: IdentityConstants) -> String {
    func arrayDeclaration(_ name: String, _ values: [String]) -> String {
        values.isEmpty
            ? "public static let \(name): [String] = []"
            : "public static let \(name) = \(swiftStringArray(values))"
    }

    let lines = [
        "public static let displayName = \(String(reflecting: identity.displayName))",
        "public static let bundleIdentifier = \(String(reflecting: identity.bundleIdentifier))",
        "public static let logSubsystem = \(String(reflecting: identity.logSubsystem))",
        "public static let appSupportDirectoryName = \(String(reflecting: identity.appSupportDirectory))",
        "public static let logDirectoryName = \(String(reflecting: identity.logDirectory))",
        "public static let keychainServiceIdentifier = \(String(reflecting: identity.keychainService))",
        "public static let appURLScheme = \(String(reflecting: identity.urlScheme))",
        "public static let hotkeySignatureSeed = \(String(reflecting: value("persistence", "hotkeySignatureSeed")))",
        "public static let userDefaultsDomainMigrationFlag = \(String(reflecting: value("persistence", "userDefaultsMigrationFlag")))",
        arrayDeclaration("legacyAppSupportDirectoryNames", identity.legacyAppSupportDirectories),
        arrayDeclaration("legacyLogDirectoryNames", identity.legacyLogDirectories),
        arrayDeclaration("legacyKeychainServiceIdentifiers", identity.legacyKeychainServices),
        arrayDeclaration("legacyUserDefaultsDomains", identity.legacyUserDefaultsDomains),
        "public static let settingsToolbarIdentifier = \(String(reflecting: value("internal", "settingsToolbarIdentifier")))",
        "public static let settingsWindowAutosaveName = \(String(reflecting: identity.settingsWindowAutosaveName))"
    ]
    return lines.map { "        " + $0 }.joined(separator: "\n")
}

let swiftDebugConstants = IdentityConstants(
    displayName: developmentValue("displayName"),
    bundleIdentifier: developmentValue("bundleIdentifier"),
    logSubsystem: developmentValue("logSubsystem"),
    appSupportDirectory: developmentValue("appSupportDirectory"),
    logDirectory: developmentValue("logDirectory"),
    keychainService: developmentValue("keychainService"),
    urlScheme: developmentValue("urlScheme"),
    settingsWindowAutosaveName: developmentValue("settingsWindowAutosaveName"),
    legacyAppSupportDirectories: [],
    legacyLogDirectories: [],
    legacyKeychainServices: [],
    legacyUserDefaultsDomains: []
)

let swiftReleaseConstants = IdentityConstants(
    displayName: value("product", "displayName"),
    bundleIdentifier: value("technical", "bundleIdentifier"),
    logSubsystem: value("technical", "logSubsystem"),
    appSupportDirectory: value("persistence", "appSupportDirectory"),
    logDirectory: value("persistence", "logDirectory"),
    keychainService: value("technical", "keychainService"),
    urlScheme: value("technical", "urlScheme"),
    settingsWindowAutosaveName: value("internal", "settingsWindowAutosaveName"),
    legacyAppSupportDirectories: legacyAppSupportDirectories,
    legacyLogDirectories: legacyLogDirectories,
    legacyKeychainServices: legacyKeychainServices,
    legacyUserDefaultsDomains: legacyUserDefaultsDomains
)

let swift = """
\(header)import Foundation

public enum AppIdentityValues {
    #if DEBUG
\(swiftConstants(swiftDebugConstants))
    #else
\(swiftConstants(swiftReleaseConstants))
    #endif
}

"""

let shell = """
#!/bin/bash
# GENERATED FILE — DO NOT EDIT. Source: Config/AppIdentity.plist.
APP_SCHEME=\(shellQuote(value("internal", "appScheme")))
APP_PRODUCT_NAME=\(shellQuote(value("product", "productName")))
APP_DEV_BUNDLE_ID=\(shellQuote(developmentValue("bundleIdentifier")))
XCODEPROJ_NAME=\(shellQuote(value("internal", "xcodeprojName")))

"""

let outputs: [(String, String)] = [
    ("Config/Branding.xcconfig", xcconfig),
    ("Packages/VerbiCore/Sources/Common/Config/AppIdentityValues.generated.swift", swift),
    ("scripts/config/app_identity.sh", shell)
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
