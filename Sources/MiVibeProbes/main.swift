import AppKit
import MiVibeCore
import Darwin

// 探针输出重定向到文件时默认块缓冲，会让挂起现场完全看不见。
setbuf(stdout, nil)

// 临时入口：真实的 SwiftUI 应用入口在步骤 3 替换掉这里。
// 现在提供 --probe-inject 用于验证注入层（对着已聚焦的输入框写入一段带标记的文字）。

let args = CommandLine.arguments

if args.contains("--probe-inject") {
    let countdown = 6.0
    print("AX=\(Permissions.hasAccessibility()) EventPost=\(Permissions.hasEventPosting())")
    print("请在 \(Int(countdown)) 秒内点击目标输入框…")
    Thread.sleep(forTimeInterval: countdown)

    guard let snapshot = TextInjector.snapshotFocus() else {
        print("未取得焦点元素（检查辅助功能权限）")
        exit(1)
    }
    let app = NSRunningApplication(processIdentifier: snapshot.pid)?.localizedName ?? "?"
    print("目标=\(app) pid=\(snapshot.pid) AXSelectedText可写=\(snapshot.selectedTextSettable) 安全框=\(snapshot.isSecure)")

    let marker = "mivibe注入🎤\(Int.random(in: 1000...9999))"
    do {
        let target = try TextInjector.inject(marker, into: snapshot)
        print("注入成功：路径=\(target) 文字=\(marker)")
    } catch {
        print("注入失败：\(error.localizedDescription)")
        exit(2)
    }
    exit(0)
}

if args.contains("--probe-asr") {
    // 用 macOS say 合成一段音频走真实识别，验证 DoubaoClient 的端到端链路。
    let sentence = args.last.flatMap { $0.hasPrefix("--") ? nil : $0 }
        ?? "你好，这是小米遥控器语音输入的识别测试。"

    let aiff = "/tmp/mivibe-asr-probe.aiff"
    let raw = "/tmp/mivibe-asr-probe.pcm"
    for (tool, toolArgs) in [
        ("/usr/bin/say", ["-o", aiff, "-r", "180", sentence]),
        ("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff, raw]),
    ] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = toolArgs
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            print("音频准备失败：\(tool)")
            exit(1)
        }
    }

    guard var pcm = FileManager.default.contents(atPath: raw) else {
        print("读不到 PCM"); exit(1)
    }
    if pcm.count > 44 { pcm = pcm.dropFirst(44) }   // 去掉 WAV 头
    let seconds = Double(pcm.count) / 32000
    print(String(format: "音频 %.2fs（%d 字节），预计费用 %.4f 元", seconds, pcm.count, seconds / 3600))

    let started = Date()
    // 不能用 semaphore.wait() 阻塞主线程：URLSession 的回调要在主线程 run loop 上
    // 派发，阻塞会自锁。改为跑 run loop 直到任务置位。
    final class Done { var value = false }
    let done = Done()
    Task {
        do {
            let client = DoubaoClient()
            await client.setVerbose(true)
            let text = try await client.transcribe(pcm: pcm)
            print(String(format: "识别成功（耗时 %.2fs）：%@", Date().timeIntervalSince(started), text))
        } catch {
            print("识别失败：\(error.localizedDescription)")
        }
        done.value = true
    }
    while !done.value, Date().timeIntervalSince(started) < 60 {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    exit(0)
}

if args.contains("--probe-seize") {
    SeizeProbe.run(voiceMode: false)
    exit(0)
}

if args.contains("--probe-remap") {
    // 方案 A：按设备 UserKeyMapping 重映射代替 HID 独占。可选 --dst 0x... 换死键候选。
    RemapProbe.run(arguments: args)
    exit(0)
}

if args.contains("--probe-seize-voice") {
    SeizeProbe.run(voiceMode: true)
    exit(0)
}

if args.contains("--probe-whisper") {
    // 裸跑（非 .app）时给 ggml 指 Metal 内核源码位置；打包后由 Resources 提供。
    setenv("GGML_METAL_PATH_RESOURCES",
           URL(fileURLWithPath: #filePath)
               .deletingLastPathComponent()  // MiVibeProbes
               .deletingLastPathComponent()  // Sources
               .deletingLastPathComponent()  // 仓库根
               .appendingPathComponent("Vendor/whisper.cpp/ggml/src/ggml-metal").path, 1)
    // 本地 whisper 端到端：say 合成 → afconvert 转 16k mono s16le → LocalWhisperProvider。
    // 用法：--probe-whisper <模型路径> [句子]
    var rest = args.dropFirst().filter { $0 != "--probe-whisper" }
    guard let modelPath = rest.first else {
        print("缺模型路径"); exit(1)
    }
    rest.removeFirst()
    let sentence = rest.first ?? "你好，这是小米遥控器语音输入的本地识别测试。"

    let aiff = "/tmp/mivibe-whisper-probe.aiff"
    let raw = "/tmp/mivibe-whisper-probe.pcm"
    for (tool, toolArgs) in [
        ("/usr/bin/say", ["-o", aiff, "-r", "180", sentence]),
        ("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff, raw]),
    ] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = toolArgs
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { print("音频准备失败：\(tool)"); exit(1) }
    }
    guard var pcm = FileManager.default.contents(atPath: raw) else { print("读不到 PCM"); exit(1) }
    if pcm.count > 44 { pcm = pcm.dropFirst(44) }

    let started = Date()
    final class Done { var value = false }
    let done = Done()
    Task {
        do {
            let provider = LocalWhisperProvider(modelURL: URL(fileURLWithPath: modelPath))
            let text = try await provider.transcribe(pcm: pcm)
            print(String(format: "本地识别成功（耗时 %.2fs）：%@", Date().timeIntervalSince(started), text))
        } catch {
            print("本地识别失败：\(error.localizedDescription)")
        }
        done.value = true
    }
    while !done.value, Date().timeIntervalSince(started) < 300 {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    exit(0)
}

if args.contains("--probe-download") {
    // 模型下载链路端到端：下载 → SHA256 校验 → 落位。用法：--probe-download [模型id，默认 tiny]
    let modelID = args.last.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? "tiny"
    guard let model = ModelCatalog.model(id: modelID) else { print("未知模型：\(modelID)"); exit(1) }
    print("下载 \(model.displayName)（\(model.sizeText)）到 \(ModelStore.modelsDir.path)")
    final class Done { var value = false }
    let done = Done()
    let started = Date()
    Task { @MainActor in
        let store = ModelStore()
        store.download(model)
        while !done.value {
            if case .downloaded = store.states[model.id] {
                print(String(format: "下载完成（%.1fs），SHA256 校验通过", Date().timeIntervalSince(started)))
                done.value = true
            } else if case .failed(let msg) = store.states[model.id] {
                print("下载失败：\(msg)")
                done.value = true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
    while !done.value, Date().timeIntervalSince(started) < 600 {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
    }
    exit(0)
}

print("MiVibe 探针。可用：")
print("  --probe-inject        验证文本注入（对着已聚焦输入框写一段标记文字）")
print("  --probe-asr [句子]    用 say 合成音频跑真实识别")
print("  --probe-whisper <模型路径> [句子]   用 say 合成音频跑本地 whisper 识别")
print("  --probe-download [模型id]          验证模型下载+校验链路（默认 tiny）")
print("  --probe-seize         HID 独占闸门：按键真实行为 + 独占能否抑制")
print("  --probe-seize-voice   独占期间 BLE 语音通道是否存活")
exit(0)
