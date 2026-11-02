// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Groundbar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Groundbar",
            path: "Sources/Groundbar",
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
