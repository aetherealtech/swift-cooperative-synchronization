// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CooperativeSynchronization",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "CooperativeSynchronization",
            targets: ["CooperativeSynchronization"]),
    ],
    dependencies: [
        .package(path: "../CoreExtensions"),
        .package(path: "../Synchronization"),
    ],
    targets: [
        .target(
            name: "CooperativeSynchronization",
            dependencies: [
                .product(name: "AsyncExtensions", package: "CoreExtensions"),
                .product(name: "CollectionExtensions", package: "CoreExtensions"),
                .product(name: "Synchronization", package: "Synchronization"),
            ]),
        .testTarget(
            name: "CooperativeSynchronizationTests",
            dependencies: [
                "CooperativeSynchronization",
                .product(name: "AsyncExtensions", package: "CoreExtensions"),
            ]),
    ]
)
