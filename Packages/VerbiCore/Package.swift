// swift-tools-version: 6.2
// Swift Package for VerbiCore library

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "VerbiCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "VerbiCore",
            targets: ["VerbiCore"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0"),
        .package(url: "https://github.com/nodes-app/swift-markdown-engine", exact: "0.6.0"),
    ],
    targets: [
        .target(
            name: "VerbiCoreCommon",
            path: "Sources/Common",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "VerbiCoreDomain",
            dependencies: [
                "VerbiCoreCommon",
                "VerbiCoreMocking",
            ],
            path: "Sources/Domain",
        ),
        .target(
            name: "VerbiCoreData",
            dependencies: [
                "VerbiCoreCommon",
                "VerbiCoreDomain",
                "VerbiCoreInfrastructure",
            ],
            path: "Sources/Data",
        ),
        .target(
            name: "VerbiCoreInfrastructure",
            dependencies: [
                "VerbiCoreCommon",
                "VerbiCoreDomain",
            ],
            path: "Sources/Infrastructure",
        ),
        .target(
            name: "VerbiCoreAudio",
            dependencies: [
                "VerbiCoreCommon",
                "VerbiCoreData",
                "VerbiCoreDomain",
                "VerbiCoreInfrastructure",
            ],
            path: "Sources/Audio",
        ),
        .target(
            name: "VerbiCoreAI",
            dependencies: [
                "VerbiCoreCommon",
                "VerbiCoreDomain",
                "VerbiCoreInfrastructure",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/AI",
        ),
        .target(
            name: "VerbiCoreUI",
            dependencies: [
                "VerbiCoreAI",
                "VerbiCoreAudio",
                "VerbiCoreCommon",
                "VerbiCoreData",
                "VerbiCoreDomain",
                "VerbiCoreInfrastructure",
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
            ],
            path: "Sources/UI",
            resources: [
                .process("Resources"),
            ],
        ),
        .target(
            name: "VerbiCore",
            dependencies: [
                "VerbiCoreAI",
                "VerbiCoreAudio",
                "VerbiCoreCommon",
                "VerbiCoreData",
                "VerbiCoreDomain",
                "VerbiCoreInfrastructure",
                "VerbiCoreUI",
            ],
            path: "Sources/Core",
        ),
        .target(
            name: "VerbiCoreMocking",
            dependencies: [
                "VerbiCoreMockingMacros",
            ],
            path: "Sources/Mocking",
        ),
        .macro(
            name: "VerbiCoreMockingMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ],
            path: "Sources/MockingMacros",
        ),
        .testTarget(
            name: "VerbiCoreTests",
            dependencies: [
                "VerbiCore",
                "VerbiCoreAI",
                "VerbiCoreAudio",
                "VerbiCoreUI",
                "VerbiCoreDomain",
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ],
            path: "Tests/VerbiCoreTests",
            resources: [
                .process("Resources"),
            ],
        ),
    ],
    swiftLanguageModes: [.v6],
)
