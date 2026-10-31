// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OmniBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OmniBar",
            path: "Sources/OmniBar",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Network"),
            ]
        )
    ]
)
