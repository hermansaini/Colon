// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EmojiDataGenerator",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "EmojiDataGeneratorCore", targets: ["EmojiDataGeneratorCore"]),
        .executable(name: "EmojiDataGenerator", targets: ["EmojiDataGenerator"]),
    ],
    dependencies: [
        .package(path: "../../Packages/ColonModels"),
    ],
    targets: [
        .target(
            name: "EmojiDataGeneratorCore",
            dependencies: [.product(name: "ColonModels", package: "ColonModels")]
        ),
        .executableTarget(
            name: "EmojiDataGenerator",
            dependencies: ["EmojiDataGeneratorCore"]
        ),
        .testTarget(
            name: "EmojiDataGeneratorCoreTests",
            dependencies: [
                "EmojiDataGeneratorCore",
                .product(name: "ColonModels", package: "ColonModels"),
            ],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
