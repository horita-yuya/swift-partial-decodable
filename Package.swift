// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-partial-decodable",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PartialDecodable",
            targets: ["PartialDecodable"]
        ),
    ],
    targets: [
        .target(
            name: "PartialDecodable"
        ),
        .testTarget(
            name: "PartialDecodableTests",
            dependencies: ["PartialDecodable"]
        ),
    ]
)
