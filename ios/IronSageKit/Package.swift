// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "IronSageKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "IronSageAPI", targets: ["IronSageAPI"]),
        .library(name: "IronSageCore", targets: ["IronSageCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.0.0"),
    ],
    targets: [
        // Client for the IronSage API, generated at build time from api/openapi.json
        // (a symlink in the target folder), so it always matches the backend's contract.
        .target(
            name: "IronSageAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        // App logic that needs no UI, so `swift test` covers it without a simulator.
        .target(name: "IronSageCore"),
        .testTarget(
            name: "IronSageAPITests",
            dependencies: ["IronSageAPI"]
        ),
        .testTarget(
            name: "IronSageCoreTests",
            dependencies: ["IronSageCore"]
        ),
    ]
)
