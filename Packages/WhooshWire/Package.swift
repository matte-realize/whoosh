// swift-tools-version: 6.0
//
// WhooshWire — the Foundation-only shared wire contract between the Whoosh
// iOS app and the WhooshWatch watchOS app (watch-companion spec, design
// "Why a shared package", Requirement 2.3).
//
// This package compiles into BOTH targets so phone and watch agree on the
// wire envelope, codec, DTOs, versioning, and the pure watch-side logic by
// sharing the same source. It imports Foundation only — never UIKit, SwiftUI,
// WatchKit, HealthKit, WatchConnectivity, CoreLocation, MapKit, AVFoundation,
// Photos, or any networking API — so it tests fast with `swift test` on a Mac
// and cannot accidentally reach a UI or system framework
// (`scripts/privacy-check.sh` rule 19 enforces this).

import PackageDescription

let package = Package(
    name: "WhooshWire",
    // watchOS 10 (owner's Apple Watch SE, O-W1) pairs with iOS 17 (the app's
    // minimum); macOS is included so `swift test` runs on a Mac without a
    // simulator (design "Why a shared package").
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(name: "WhooshWire", targets: ["WhooshWire"]),
    ],
    targets: [
        .target(
            name: "WhooshWire",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "WhooshWireTests",
            dependencies: ["WhooshWire"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
