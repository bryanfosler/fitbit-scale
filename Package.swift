// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FitbitScaleCore",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "FitbitScaleCore",
            targets: ["FitbitScaleCore"]
        ),
        .executable(
            name: "fitbit-scale-exporter",
            targets: ["FitbitScaleExporter"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "FitbitScaleCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
            ]
        ),
        .executableTarget(
            name: "FitbitScaleExporter",
            dependencies: ["FitbitScaleCore"]
        ),
        .testTarget(
            name: "FitbitScaleCoreTests",
            dependencies: ["FitbitScaleCore"]
        )
    ]
)
