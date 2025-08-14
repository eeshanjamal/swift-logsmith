// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: Array<SwiftSetting> = [
    .enableUpcomingFeature("ConciseMagicFile"),
    .enableUpcomingFeature("BareSlashRegexLiterals"),
    .enableUpcomingFeature("DeprecateApplicationMain"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("ForwardTrailingClosures"),
    .enableUpcomingFeature("IsolatedDefaultValues"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableExperimentalFeature("GlobalConcurrency"),
    .enableExperimentalFeature("StrictConcurrency"),
    .enableExperimentalFeature("AccessLevelOnImport"),
]

let package = Package(
    name: "swift-logsmith",
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
