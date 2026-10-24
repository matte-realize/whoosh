// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WhooshVision",
    // macOS is listed so the detector and its tests run with `swift test` on a Mac.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WhooshVision", targets: ["WhooshVision"])],
    targets: [
        .target(name: "WhooshVision", resources: [.copy("Resources/yolo26n.mlpackage")]),
        .testTarget(name: "WhooshVisionTests", dependencies: ["WhooshVision"],
                    resources: [.copy("Resources/bus.jpg")]),
    ],
    swiftLanguageModes: [.v5]
)
