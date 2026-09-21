// swift-tools-version: 6.0
import PackageDescription

// MiVibe：小米遥控器 → 豆包语音 → macOS 跨应用文本输入。
// 除 vendored 的 whisper.cpp（本地识别引擎，见 Scripts/fetch-whisper.sh）外无外部依赖，
// 全部使用系统框架（SwiftUI/AppKit/CoreBluetooth/IOKit/ApplicationServices）。
// SwiftPM 只产出裸可执行文件；.app bundle 由 Scripts/build-app.sh 组装（本机无 Xcode）。

// whisper.cpp（v1.9.4）源码清单：对齐其 CMake 的 macOS 静态构建
// （ggml-base + ggml 前端注册层 + ggml-cpu/ARM + ggml-metal + whisper 本体）。
// Metal 内核不预编译 metallib（metal 编译器只在 Xcode 里），走运行时源码编译：
// 内核 .metal 文件由 build-app.sh 拷进 .app Resources/kernels/。
let whisperSources = [
    // ggml-base
    "ggml/src/ggml.c",
    "ggml/src/ggml.cpp",
    "ggml/src/ggml-alloc.c",
    "ggml/src/ggml-backend.cpp",
    "ggml/src/ggml-backend-meta.cpp",
    "ggml/src/ggml-opt.cpp",
    "ggml/src/ggml-threading.cpp",
    "ggml/src/ggml-quants.c",
    "ggml/src/gguf.cpp",
    // ggml 前端（静态注册后端 + dl 层：reg 里无条件引用 dl_* 符号）
    "ggml/src/ggml-backend-reg.cpp",
    "ggml/src/ggml-backend-dl.cpp",
    // ggml-cpu（ARM）
    "ggml/src/ggml-cpu/ggml-cpu.c",
    "ggml/src/ggml-cpu/ggml-cpu.cpp",
    "ggml/src/ggml-cpu/repack.cpp",
    "ggml/src/ggml-cpu/iqp.cpp",
    "ggml/src/ggml-cpu/hbm.cpp",
    "ggml/src/ggml-cpu/quants.c",
    "ggml/src/ggml-cpu/traits.cpp",
    "ggml/src/ggml-cpu/binary-ops.cpp",
    "ggml/src/ggml-cpu/unary-ops.cpp",
    "ggml/src/ggml-cpu/vec.cpp",
    "ggml/src/ggml-cpu/ops.cpp",
    "ggml/src/ggml-cpu/amx/amx.cpp",
    "ggml/src/ggml-cpu/amx/mmq.cpp",
    "ggml/src/ggml-cpu/arch/arm/cpu-feats.cpp",
    "ggml/src/ggml-cpu/arch/arm/quants.c",
    "ggml/src/ggml-cpu/arch/arm/repack.cpp",
    // ggml-metal
    "ggml/src/ggml-metal/ggml-metal.cpp",
    "ggml/src/ggml-metal/ggml-metal-common.cpp",
    "ggml/src/ggml-metal/ggml-metal-context.m",
    "ggml/src/ggml-metal/ggml-metal-device.m",
    "ggml/src/ggml-metal/ggml-metal-device.cpp",
    "ggml/src/ggml-metal/ggml-metal-ops.cpp",
    "ggml/src/ggml-metal/ggml-metal-tuning.cpp",
    // whisper 本体
    "src/whisper.cpp",
]

// target path 是整棵源码树，除清单外的内容全部排除（尤其 kernels/*.metal——
// 它们是运行时资源，让 SPM 碰它们会触发 metal 工具链报错）。
let whisperExcludes = [
    ".devops", ".github", ".pi", "bindings", "ci", "cmake", "examples", "grammars",
    "media", "models", "scripts", "tests",
    "AGENTS.md", "AUTHORS", "CMakeLists.txt", "CMakePresets.json", "CONTRIBUTING.md",
    "LICENSE", "Makefile", "README.md", "README_sycl.md", ".dockerignore", ".gitignore",
    "src/CMakeLists.txt", "src/coreml", "src/openvino", "src/vitisai",
    "src/parakeet.cpp", "src/parakeet-arch.h",
    "ggml/CMakeLists.txt", "ggml/cmake",
    "ggml/src/CMakeLists.txt", "ggml/src/ggml-version.h.in",
    "ggml/src/ggml-blas", "ggml/src/ggml-cann", "ggml/src/ggml-hexagon",
    "ggml/src/ggml-opencl", "ggml/src/ggml-openvino", "ggml/src/ggml-rpc",
    "ggml/src/ggml-sycl", "ggml/src/ggml-virtgpu", "ggml/src/ggml-vulkan",
    "ggml/src/ggml-webgpu", "ggml/src/ggml-zdnn", "ggml/src/ggml-zendnn",
    "ggml/src/ggml-cpu/cmake", "ggml/src/ggml-cpu/kleidiai", "ggml/src/ggml-cpu/llamafile",
    "ggml/src/ggml-cpu/spacemit", "ggml/src/ggml-cpu/CMakeLists.txt",
    "ggml/src/ggml-cpu/arch/loongarch", "ggml/src/ggml-cpu/arch/powerpc",
    "ggml/src/ggml-cpu/arch/riscv", "ggml/src/ggml-cpu/arch/s390",
    "ggml/src/ggml-cpu/arch/wasm", "ggml/src/ggml-cpu/arch/x86",
    "ggml/src/ggml-metal/CMakeLists.txt",
]

let package = Package(
    name: "MiVibe",
    platforms: [.macOS(.v14)],
    targets: [
        // 本地识别引擎：vendored whisper.cpp（先跑 Scripts/fetch-whisper.sh）。
        // 头文件搜索路径里的 ../../Sources/CWhisperShim 提供 CMake 本该生成的
        // ggml-version.h。
        .target(
            name: "CWhisper",
            path: "Vendor/whisper.cpp",
            exclude: whisperExcludes,
            sources: whisperSources,
            // Metal 内核与 flatten 需要的头文件作为资源进 MiVibe_CWhisper.bundle
            // （SWIFT_PACKAGE 路径下 ggml 从该 bundle 找 kernels/*.metal 并运行时编译）。
            // build-app.sh 需把这个 bundle 一并拷进 .app 的 Contents/Resources/。
            resources: [
                .copy("ggml/src/ggml-metal/kernels"),
                .copy("ggml/src/ggml-common.h"),
                .copy("ggml/src/ggml-metal/ggml-metal-impl.h"),
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("ggml/include"),
                .headerSearchPath("ggml/src"),
                .headerSearchPath("ggml/src/ggml-cpu"),
                .headerSearchPath("ggml/src/ggml-metal"),
                .headerSearchPath("../../Sources/CWhisperShim"),
                .define("GGML_USE_CPU"),
                .define("GGML_USE_METAL"),
                .define("GGML_USE_ACCELERATE"),
                .define("WHISPER_VERSION", to: "\"1.9.4\""),
                .define("GGML_METAL_NDEBUG", .when(configuration: .release)),
                // ggml-metal 的 .m 是手写 MRC（retain/release），SPM 默认开 ARC。
                // -USWIFT_PACKAGE：ggml 对 SPM 的特判是从 MiVibe_CWhisper.bundle 找
                // Metal 内核，但该 bundle 放不进签名 .app 的合法位置（bundle 根目录
                // 只允许 Contents）。撤掉这个宏让它走 mainBundle，内核由
                // build-app.sh 拷进 Contents/Resources/kernels/。
                .unsafeFlags(["-fno-objc-arc", "-USWIFT_PACKAGE", "-Wno-shorten-64-to-32", "-Wno-unused-function"]),
            ],
            cxxSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("ggml/include"),
                .headerSearchPath("ggml/src"),
                .headerSearchPath("ggml/src/ggml-cpu"),
                .headerSearchPath("ggml/src/ggml-metal"),
                .headerSearchPath("../../Sources/CWhisperShim"),
                .define("GGML_USE_CPU"),
                .define("GGML_USE_METAL"),
                .define("GGML_USE_ACCELERATE"),
                .define("GGML_METAL_NDEBUG", .when(configuration: .release)),
                .unsafeFlags(["-Wno-shorten-64-to-32", "-Wno-unused-function"]),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),
        // 纯逻辑：可脱离 UI 与硬件测试（ADPCM 解码、豆包帧编解码、输入队列状态机）。
        .target(
            name: "MiVibeCore",
            dependencies: ["CWhisper"],
            path: "Sources/MiVibeCore"
        ),
        // 应用本体：UI 与系统集成（CoreBluetooth / IOHID / AX 注入）。
        .executableTarget(
            name: "MiVibe",
            dependencies: ["MiVibeCore"],
            path: "Sources/MiVibe",
            resources: [.process("Resources")]
        ),
        // 诊断探针：与应用共享 Core，但独立入口（main.swift 不能和 @main 共存）。
        .executableTarget(
            name: "MiVibeProbes",
            dependencies: ["MiVibeCore"],
            path: "Sources/MiVibeProbes"
        ),
        // 本机只有 Command Line Tools：XCTest 与 swift-testing 的 .swiftmodule 都不存在
        // （框架二进制在，模块接口缺失），`swift test` 无法用。因此测试是一个自带
        // 断言辅助的可执行目标：`swift run MiVibeTests`，失败时退出码非 0。
        .executableTarget(
            name: "MiVibeTests",
            dependencies: ["MiVibeCore"],
            path: "Tests/MiVibeTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
