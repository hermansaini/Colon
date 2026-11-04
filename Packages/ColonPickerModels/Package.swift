// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ColonPickerModels",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ColonPickerModels", targets: ["ColonPickerModels"]),
    ],
    dependencies: [
        .package(path: "../ColonModels"),
    ],
    targets: [
        .target(
            name: "ColonPickerModels",
            dependencies: [.product(name: "ColonModels", package: "ColonModels")]
        ),
        .testTarget(
            name: "ColonPickerModelsTests",
            dependencies: [
                "ColonPickerModels",
                .product(name: "ColonModels", package: "ColonModels"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
