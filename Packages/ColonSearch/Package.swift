// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ColonSearch",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ColonSearch", targets: ["ColonSearch"]),
    ],
    dependencies: [
        .package(path: "../ColonModels"),
        .package(path: "../ColonEmojiData"),
        .package(path: "../ColonTokenization"),
    ],
    targets: [
        .target(
            name: "ColonSearch",
            dependencies: [
                .product(name: "ColonModels", package: "ColonModels"),
                .product(name: "ColonEmojiData", package: "ColonEmojiData"),
                .product(name: "ColonTokenization", package: "ColonTokenization"),
            ]
        ),
        .testTarget(
            name: "ColonSearchTests",
            dependencies: [
                "ColonSearch",
                .product(name: "ColonModels", package: "ColonModels"),
                .product(name: "ColonEmojiData", package: "ColonEmojiData"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
