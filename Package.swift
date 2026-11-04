// swift-tools-version: 6.0
// Desktop integration tests only. Shipping apps are built by Colon.xcworkspace.
import PackageDescription

let package = Package(
    name: "ColonDesktopTests",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(path: "Packages/ColonModels"),
        .package(path: "Packages/ColonEmojiData"),
        .package(path: "Packages/ColonSearch"),
        .package(path: "Packages/ColonTokenization"),
        .package(path: "Packages/ColonPickerModels"),
        .package(path: "Packages/ColonSettingsCore"),
    ],
    targets: [
        .executableTarget(
            name: "ColonBenchmark",
            dependencies: [
                .product(name: "ColonEmojiData", package: "ColonEmojiData"),
                .product(name: "ColonSearch", package: "ColonSearch"),
            ],
            path: "Tools/ColonBenchmark"
        ),
        .target(
            name: "ColonCompanion",
            dependencies: [
                .product(name: "ColonModels", package: "ColonModels"),
                .product(name: "ColonEmojiData", package: "ColonEmojiData"),
                .product(name: "ColonSearch", package: "ColonSearch"),
                .product(name: "ColonTokenization", package: "ColonTokenization"),
                .product(name: "ColonPickerModels", package: "ColonPickerModels"),
                .product(name: "ColonSettingsCore", package: "ColonSettingsCore"),
            ],
            path: "Apps/ColonMacApp/App",
            exclude: ["ColonMacApp.swift"]
        ),
        .testTarget(
            name: "ColonCompanionTests",
            dependencies: ["ColonCompanion"],
            path: "Tests/Companion"
        ),
    ],
    swiftLanguageModes: [.v6]
)
