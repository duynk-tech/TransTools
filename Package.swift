// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TransTools",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TransTools", targets: ["TransTools"])
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager.git", exact: "1.24.2")
    ],
    targets: [
        .executableTarget(
            name: "TransTools",
            dependencies: [
                "LocalSpeechBackend"
            ]
        ),
        .target(
            name: "LocalSpeechBackend",
            dependencies: [
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")
            ]
        ),
        .testTarget(
            name: "LocalTTSTests",
            dependencies: ["TransTools", "LocalSpeechBackend"],
            path: "Tests/LocalTTSTests",
            exclude: ["vieneu-sdk-golden.json"]
        )
    ]
)
