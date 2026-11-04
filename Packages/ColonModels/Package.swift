// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ColonModels",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ColonModels", targets: ["ColonModels"]),
    ],
    targets: [
        .target(name: "ColonModels"),
        .testTarget(name: "ColonModelsTests", dependencies: ["ColonModels"]),
    ],
    swiftLanguageModes: [.v6]
)
