// swift-tools-version: 5.9

import PackageDescription

let nativeDefines: [CSetting] = [
    .define("GGML_USE_CPU"),
    .define("GGML_USE_BLAS"),
    .define("GGML_BLAS_USE_ACCELERATE"),
    .define("GGML_USE_ACCELERATE"),
    .define("GGML_USE_METAL"),
    .define("WHISPER_USE_COREML"),
    .define("WHISPER_COREML_ALLOW_FALLBACK"),
    .define("ACCELERATE_NEW_LAPACK"),
    .define("ACCELERATE_LAPACK_ILP64"),
    .define("WHISPER_VERSION", to: "\"1.9.2\""),
    .define("GGML_VERSION", to: "\"0.18.1\""),
    .define("GGML_COMMIT", to: "\"unknown\""),
]

let nativeCxxDefines: [CXXSetting] = [
    .define("GGML_USE_CPU"),
    .define("GGML_USE_BLAS"),
    .define("GGML_BLAS_USE_ACCELERATE"),
    .define("GGML_USE_ACCELERATE"),
    .define("GGML_USE_METAL"),
    .define("WHISPER_USE_COREML"),
    .define("WHISPER_COREML_ALLOW_FALLBACK"),
    .define("ACCELERATE_NEW_LAPACK"),
    .define("ACCELERATE_LAPACK_ILP64"),
    .define("WHISPER_VERSION", to: "\"1.9.2\""),
    .define("GGML_VERSION", to: "\"0.18.1\""),
    .define("GGML_COMMIT", to: "\"unknown\""),
]

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
        .target(
            name: "WhisperCppCore",
            dependencies: ["WhisperCppGgml"],
            path: "Sources/WhisperCppCore",
            exclude: [
                ".devops",
                ".github",
                ".pi",
                "bindings",
                "ci",
                "cmake",
                "examples",
                "ggml",
                "grammars",
                "media",
                "models",
                "samples",
                "scripts",
                "tests",
            ],
            sources: [
                "src/whisper.cpp",
                "src/coreml",
            ],
            publicHeadersPath: "include",
            cSettings: nativeDefines,
            cxxSettings: nativeCxxDefines,
            linkerSettings: [
                .linkedFramework("CoreML"),
                .linkedFramework("Foundation"),
                .linkedLibrary("c++"),
            ]
        ),
        .target(
            name: "WhisperCppGgml",
            path: "Sources/WhisperCppCore/ggml",
            exclude: [
                "src/ggml-metal/ggml-metal.metal",
            ],
            sources: [
                "src/ggml.c",
                "src/ggml.cpp",
                "src/ggml-alloc.c",
                "src/ggml-backend.cpp",
                "src/ggml-backend-dl.cpp",
                "src/ggml-backend-meta.cpp",
                "src/ggml-backend-reg.cpp",
                "src/ggml-opt.cpp",
                "src/ggml-quants.c",
                "src/ggml-threading.cpp",
                "src/gguf.cpp",
                "src/ggml-cpu/ggml-cpu.c",
                "src/ggml-cpu/ggml-cpu.cpp",
                "src/ggml-cpu/repack.cpp",
                "src/ggml-cpu/hbm.cpp",
                "src/ggml-cpu/quants.c",
                "src/ggml-cpu/traits.cpp",
                "src/ggml-cpu/amx/amx.cpp",
                "src/ggml-cpu/amx/mmq.cpp",
                "src/ggml-cpu/binary-ops.cpp",
                "src/ggml-cpu/unary-ops.cpp",
                "src/ggml-cpu/vec.cpp",
                "src/ggml-cpu/ops.cpp",
                "spm/ggml-arch-quants.c",
                "spm/ggml-arch-repack.cpp",
                "src/ggml-blas/ggml-blas.cpp",
                "src/ggml-metal/ggml-metal-common.cpp",
                "src/ggml-metal/ggml-metal-context.m",
                "src/ggml-metal/ggml-metal-device.cpp",
                "src/ggml-metal/ggml-metal-device.m",
                "src/ggml-metal/ggml-metal-ops.cpp",
                "src/ggml-metal/ggml-metal.cpp",
            ],
            resources: [
                .copy("Resources/ggml-metal.txt"),
                .copy("src/ggml-metal/ggml-metal-impl.h"),
                .copy("src/ggml-common.h"),
            ],
            publicHeadersPath: "include",
            cSettings: nativeDefines + [
                .unsafeFlags(["-fno-objc-arc"]),
                .headerSearchPath("src"),
                .headerSearchPath("src/ggml-cpu"),
                .headerSearchPath("src/ggml-metal"),
            ],
            cxxSettings: nativeCxxDefines + [
                .headerSearchPath("src"),
                .headerSearchPath("src/ggml-cpu"),
                .headerSearchPath("src/ggml-metal"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedLibrary("c++"),
            ]
        ),
        .target(
            name: "WhisperCppFlutterBridge",
            dependencies: ["WhisperCppCore"],
            path: "Sources/WhisperCppFlutterBridge",
            sources: ["whisper_flutter.cpp"],
            publicHeadersPath: "."
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
