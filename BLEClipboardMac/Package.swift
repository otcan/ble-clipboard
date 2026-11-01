// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BLEClipboardMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BLEClipboardMac", targets: ["BLEClipboardMac"]),
    ],
    targets: [
        .executableTarget(name: "BLEClipboardMac"),
        .testTarget(name: "BLEClipboardMacTests", dependencies: ["BLEClipboardMac"]),
    ],
    swiftLanguageVersions: [.v5]
)
