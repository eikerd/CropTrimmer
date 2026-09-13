// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CropTrimmer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CropTrimmer", targets: ["CropTrimmer"]), .library(name: "CropTrimmerCore", targets: ["CropTrimmerCore"])],
    targets: [
        .target(name: "CropTrimmerCore"),
        .executableTarget(name: "CropTrimmer", dependencies: ["CropTrimmerCore"]),
        .testTarget(name: "CropTrimmerCoreTests", dependencies: ["CropTrimmerCore", "CropTrimmer"])
    ],
    swiftLanguageModes: [.v5]
)
