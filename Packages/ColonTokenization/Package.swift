// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ColonTokenization",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ColonTokenization", targets: ["ColonTokenization"]),
    ],
    targets: [
        .target(name: "ColonTokenization"),
        .testTarget(name: "ColonTokenizationTests", dependencies: ["ColonTokenization"]),
    ],
    swiftLanguageModes: [.v6]
)
