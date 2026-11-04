// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ColonEmojiData",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ColonEmojiData", targets: ["ColonEmojiData"]),
    ],
    dependencies: [
        .package(path: "../ColonModels"),
    ],
    targets: [
        .target(
            name: "ColonEmojiData",
            dependencies: [.product(name: "ColonModels", package: "ColonModels")],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ColonEmojiDataTests", dependencies: ["ColonEmojiData"]),
    ],
    swiftLanguageModes: [.v6]
)
