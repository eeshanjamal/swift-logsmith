// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: Array<SwiftSetting> = [
    .swiftLanguageMode(.v6),
    .strictMemorySafety(),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures")
]

let supportedPlatforms: Array<SupportedPlatform> = [
    .macOS(.v11),
    .iOS(.v14),
    .tvOS(.v14),
    .watchOS(.v7),
    .visionOS(.v1),
]

let package = Package(
    name: "swift-logsmith",
    platforms: supportedPlatforms,
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftLogSmith",
            targets: ["SwiftLogSmith"]),
        // Opt-in swift-log backend. Requires Swift 6.2+, so it is absent from the
        // Package@swift-6.0.swift and Package@swift-6.1.swift manifests.
        .library(
            name: "SwiftLogSmithBackend",
            targets: ["SwiftLogSmithBackend"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.11.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftLogSmith",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            swiftSettings: swiftSettings),
        .target(
            name: "SwiftLogSmithBackend",
            dependencies: [
                "SwiftLogSmith",
                .product(name: "Logging", package: "swift-log")
            ],
            swiftSettings: swiftSettings),
        .testTarget(
            name: "SwiftLogSmithTests",
            dependencies: ["SwiftLogSmith"]
        ),
        .testTarget(
            name: "SwiftLogSmithBackendTests",
            dependencies: ["SwiftLogSmithBackend"]
        ),
    ]
)
