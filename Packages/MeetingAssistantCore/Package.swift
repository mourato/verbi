// swift-tools-version: 6.2
// Swift Package for MeetingAssistantCore library

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "MeetingAssistantCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "MeetingAssistantCore",
            targets: ["MeetingAssistantCore"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/altic-dev/FluidAudio.git", revision: "3fd63887eef1dc25edea8263ce4b44aa854d898b"),
        .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0"),
        .package(url: "https://github.com/nodes-app/swift-markdown-engine", exact: "0.6.0"),
    ],
    targets: [
        .target(
            name: "MeetingAssistantCoreCommon",
            path: "Sources/Common",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "MeetingAssistantCoreDomain",
            dependencies: [
                "MeetingAssistantCoreCommon",
                "MeetingAssistantCoreMocking",
            ],
            path: "Sources/Domain",
        ),
        .target(
            name: "MeetingAssistantCoreData",
            dependencies: [
                "MeetingAssistantCoreCommon",
                "MeetingAssistantCoreDomain",
                "MeetingAssistantCoreInfrastructure",
            ],
            path: "Sources/Data",
        ),
        .target(
            name: "MeetingAssistantCoreInfrastructure",
            dependencies: [
                "MeetingAssistantCoreCommon",
                "MeetingAssistantCoreDomain",
            ],
            path: "Sources/Infrastructure",
        ),
        .target(
            name: "MeetingAssistantCoreAudio",
            dependencies: [
                "MeetingAssistantCoreCommon",
                "MeetingAssistantCoreData",
                "MeetingAssistantCoreDomain",
                "MeetingAssistantCoreInfrastructure",
                .product(name: "Atomics", package: "swift-atomics"),
            ],
            path: "Sources/Audio",
        ),
        .target(
            name: "MeetingAssistantCoreAI",
            dependencies: [
                "MeetingAssistantCoreCommon",
                "MeetingAssistantCoreDomain",
                "MeetingAssistantCoreInfrastructure",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/AI",
        ),
        .target(
            name: "MeetingAssistantCoreUI",
            dependencies: [
                "MeetingAssistantCoreAI",
                "MeetingAssistantCoreAudio",
                "MeetingAssistantCoreCommon",
                "MeetingAssistantCoreData",
                "MeetingAssistantCoreDomain",
                "MeetingAssistantCoreInfrastructure",
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
            ],
            path: "Sources/UI",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "MeetingAssistantCore",
            dependencies: [
                "MeetingAssistantCoreAI",
                "MeetingAssistantCoreAudio",
                "MeetingAssistantCoreCommon",
                "MeetingAssistantCoreData",
                "MeetingAssistantCoreDomain",
                "MeetingAssistantCoreInfrastructure",
                "MeetingAssistantCoreUI",
            ],
            path: "Sources/Core",
        ),
        .target(
            name: "MeetingAssistantCoreMocking",
            dependencies: [
                "MeetingAssistantCoreMockingMacros",
            ],
            path: "Sources/Mocking",
        ),
        .macro(
            name: "MeetingAssistantCoreMockingMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ],
            path: "Sources/MockingMacros",
        ),
        .testTarget(
            name: "MeetingAssistantCoreTests",
            dependencies: [
                "MeetingAssistantCore",
                "MeetingAssistantCoreAI",
                "MeetingAssistantCoreAudio",
                "MeetingAssistantCoreUI",
                "MeetingAssistantCoreDomain",
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ],
            path: "Tests/MeetingAssistantCoreTests",
            resources: [
                .process("Resources"),
            ],
        ),
    ],
    swiftLanguageModes: [.v6],
)
