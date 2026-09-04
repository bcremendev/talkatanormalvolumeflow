// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "talkatanormalvolumeflow",
    platforms: [.macOS(.v14)],
    targets: [
        // Prebuilt whisper.cpp (Metal-accelerated) from the official GitHub release.
        .binaryTarget(name: "whisper", path: "vendor/build-apple/whisper.xcframework"),
        .executableTarget(
            name: "talkatanormalvolumeflow",
            dependencies: ["whisper"],
            path: "Sources/App",
            linkerSettings: [
                .unsafeFlags([
                    // Inside the .app bundle
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    // For `swift run` during development
                    "-Xlinker", "-rpath", "-Xlinker",
                    "\(Context.packageDirectory)/vendor/build-apple/whisper.xcframework/macos-arm64_x86_64",
                ]),
            ]
        ),
    ]
)
