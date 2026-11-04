// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ColonSettingsCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ColonSettingsCore", targets: ["ColonSettingsCore"]),
    ],
    dependencies: [
        .package(path: "../ColonModels"),
    ],
    targets: [
        .target(
            name: "ColonSettingsCore",
            dependencies: [.product(name: "ColonModels", package: "ColonModels")]
        ),
        .testTarget(name: "ColonSettingsCoreTests", dependencies: ["ColonSettingsCore"]),
    ],
    swiftLanguageModes: [.v6]
)
