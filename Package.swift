// swift-tools-version: 6.0
import PackageDescription

// MiVibe：小米遥控器 → 豆包语音 → macOS 跨应用文本输入。
// 无外部依赖，全部使用系统框架（SwiftUI/AppKit/CoreBluetooth/IOKit/ApplicationServices）。
// SwiftPM 只产出裸可执行文件；.app bundle 由 Scripts/build-app.sh 组装（本机无 Xcode）。
let package = Package(
    name: "MiVibe",
    platforms: [.macOS(.v14)],
    targets: [
        // 纯逻辑：可脱离 UI 与硬件测试（ADPCM 解码、豆包帧编解码、输入队列状态机）。
        .target(
            name: "MiVibeCore",
            path: "Sources/MiVibeCore"
        ),
        // 应用本体：UI 与系统集成（CoreBluetooth / IOHID / AX 注入）。
        .executableTarget(
            name: "MiVibe",
            dependencies: ["MiVibeCore"],
            path: "Sources/MiVibe"
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
    ]
)
