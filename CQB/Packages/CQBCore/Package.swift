// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CQBCore",
    platforms: [
        .iOS("17.6")
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "CQBCore",
            targets: ["CQBCore"]
        ),
        .library(
            name: "CQBFixtures",
            targets: ["CQBFixtures"]
        ),
        .library(
            name: "CQBFirebase",
            targets: ["CQBFirebase"]
        ),
        .library(
            name: "CQBDesignSystem",
            targets: ["CQBDesignSystem"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "CQBCore",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "CQBFixtures",
            dependencies: ["CQBCore"],
            resources: [.copy("Resources/FloorPlans")],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "CQBFirebase",
            dependencies: ["CQBCore"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "CQBDesignSystem",
            dependencies: ["CQBCore"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "CQBFixturesTests",
            dependencies: ["CQBFixtures"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "CQBCoreTests",
            dependencies: ["CQBCore"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
