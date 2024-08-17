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
            targets: ["CooperativeSynchronization"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/aetherealtech/swift-core-extensions", branch: "master"),
        .package(url: "https://github.com/aetherealtech/swift-synchronization", branch: "master"),
    ],
    targets: [
        .target(
            name: "CooperativeSynchronization",
            dependencies: [
                .product(name: "AsyncExtensions", package: "swift-core-extensions"),
                .product(name: "CollectionExtensions", package: "swift-core-extensions"),
                .product(name: "Synchronization", package: "swift-synchronization"),
            ],
            swiftSettings: [.concurrencyChecking(.complete)]
        ),
        .testTarget(
            name: "CooperativeSynchronizationTests",
            dependencies: [
                "CooperativeSynchronization",
                .product(name: "AsyncCollectionExtensions", package: "swift-core-extensions"),
                .product(name: "AsyncExtensions", package: "swift-core-extensions"),
            ],
            swiftSettings: [.concurrencyChecking(.complete)]
        ),
    ]
)

extension SwiftSetting {
    enum ConcurrencyChecking: String {
        case complete
        case minimal
        case targeted
    }
    
    static func concurrencyChecking(_ setting: ConcurrencyChecking = .minimal) -> Self {
        unsafeFlags([
            "-Xfrontend", "-strict-concurrency=\(setting)",
            "-Xfrontend", "-warn-concurrency",
            "-Xfrontend", "-enable-actor-data-race-checks",
        ])
    }
}
