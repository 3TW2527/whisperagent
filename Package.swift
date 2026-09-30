// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperLectures",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "WhisperLectures",
            targets: ["WhisperLectures"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "WhisperLectures",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources",
            exclude: [
                "Resources/Info.plist",
                "Resources/WhisperLectures.entitlements"
            ]
        )
    ]
)
