// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tessera",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "Tessera",
            targets: ["Tessera"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Tessera",
            path: "Sources/Tessera",
            exclude: [
                "Resources/Info.plist",
                "Resources/Tessera.entitlements"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "TesseraTests",
            dependencies: ["Tessera"],
            path: "Tests/TesseraTests"
        )
    ]
)

