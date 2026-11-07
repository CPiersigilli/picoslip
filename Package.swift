// swift-tools-version: 6.2
// PicoSlip for macOS. Open this file with Xcode, choose the PicoSlip scheme
// and press Run. The Windows app keeps its own build (build.cmd).
import PackageDescription

let package = Package(
    name: "PicoSlip",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "PicoSlip", targets: ["PicoSlip"])
    ],
    targets: [
        // Portable C17 core shared with the Windows build (no OS headers).
        .target(
            name: "PicoCore",
            path: "core",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-Wall", "-Wextra", "-Werror", "-Wconversion", "-pedantic"])]
        ),
        // Swift-friendly wrappers over PicoCore; no UI.
        .target(
            name: "PicoKit",
            dependencies: ["PicoCore"],
            path: "macos/PicoKit"
        ),
        // The menu-bar app: SwiftUI with AppKit where SwiftUI cannot reach.
        .executableTarget(
            name: "PicoSlip",
            dependencies: ["PicoKit"],
            path: "macos/PicoSlip",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "PicoKitTests",
            dependencies: ["PicoKit", "PicoCore"],
            path: "macos/Tests/PicoKitTests"
        )
    ],
    swiftLanguageModes: [.v6],
    cLanguageStandard: .c17
)
