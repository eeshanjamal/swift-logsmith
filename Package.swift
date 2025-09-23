// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: Array<SwiftSetting> = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
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
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftLogSmith",
            swiftSettings: swiftSettings),
        .testTarget(
            name: "SwiftLogSmithTests",
            dependencies: ["SwiftLogSmith"]
        ),
    ]
)
