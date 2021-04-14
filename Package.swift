// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "blimp",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(url: "https://github.com/vapor/websocket-kit", from: "2.1.2"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "blimp",
            dependencies: [
                .product(name: "WebSocketKit", package: "websocket-kit"),
                .product(name: "AsyncHTTPClient", package: "async-http-client")
            ]
        ),
        .testTarget(
            name: "blimpTests",
            dependencies: ["blimp"]),
        
    ]
)
