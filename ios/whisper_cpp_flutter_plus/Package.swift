// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "whisper_cpp_flutter_plus",
    platforms: [
        .iOS("14.0"),
    ],
    products: [
        .library(
            name: "whisper-cpp-flutter-plus",
            targets: ["whisper_cpp_flutter_plus"]
        ),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .binaryTarget(
            name: "whisper",
            path: "Frameworks/whisper.xcframework"
        ),
        .target(
            name: "WhisperCppFlutterBridge",
            dependencies: ["whisper"],
            path: "Sources/WhisperCppFlutterBridge",
            sources: ["whisper_flutter.cpp"],
            publicHeadersPath: ".",
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedLibrary("c++"),
            ]
        ),
        .target(
            name: "whisper_cpp_flutter_plus",
            dependencies: [
                .product(
                    name: "FlutterFramework",
                    package: "FlutterFramework"
                ),
                "WhisperCppFlutterBridge",
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Foundation"),
                .linkedFramework("UIKit"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
