import AppKit
import CoreGraphics
import IOKit.hid
import MiVibeCore

/// HID 独占探针：按键映射功能的 go/no-go 闸门。
///
/// 为什么必须先测：`kIOHIDOptionsTypeSeizeDevice` 是**整设备**的开关，不是单键开关。
/// 一旦独占成功，macOS 就完全不再翻译这支遥控器的 HID 报文——所有按键都归 MiVibe 处置，
/// 包括我们没打算映射的音量键。而下列三件事全部没有实测证据：
///
/// 1. 独占能否成功（系统可能已持有该设备 → `kIOReturnExclusiveAccess`）。
/// 2. 独占后 BLE 语音通道是否还活着（HID 走 IOHIDManager、音频走 CoreBluetooth，
///    理论上是两条独立通道，理论上）。
/// 3. 独占期间 HOGP 链路会不会被系统断掉（`bluetoothd` 原本持有这个键盘连接）。
///
/// 任何一条不成立，按键映射就不能按"接管"模型做。
enum SeizeProbe {
    private static let vendorID = 0x2717
    private static let productID = 0x32B8

    /// 探针里需要一个能跨回调共享的可变状态。单线程（主 run loop）使用，
    /// 用 class + 锁保护，避免 Swift 6 并发检查的全局可变状态报错。
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [String] = []
        private var _removed = false

        var events: [String] {
            lock.lock(); defer { lock.unlock() }
            return _events
        }
        var deviceRemoved: Bool {
            lock.lock(); defer { lock.unlock() }
            return _removed
        }
        func add(_ line: String) {
            lock.lock(); defer { lock.unlock() }
            _events.append(line)
        }
        func markRemoved() {
            lock.lock(); defer { lock.unlock() }
            _removed = true
        }
    }

    // MARK: - 入口

    static func run(voiceMode: Bool) {
        print("═══ MiVibe HID 独占探针 ═══")
        print("设备：VID 0x\(String(vendorID, radix: 16)) PID 0x\(String(productID, radix: 16))")
        print("")

        reportAccess()

        if voiceMode {
            runVoiceMode()
        } else {
            runKeyMode()
        }
    }

    /// HID 监听的 TCC 预检。没授权的话独占多半会被拒，先把它打出来。
    private static func reportAccess() {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            print("▸ 输入监控权限：已授权")
        case kIOHIDAccessTypeDenied:
            print("▸ 输入监控权限：已拒绝 ← 独占几乎肯定失败，请先到「隐私与安全性 → 输入监控」授权")
        default:
            print("▸ 输入监控权限：未决定，正在请求…")
            let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            print("  请求结果：\(granted ? "已授权" : "未授权（可能弹了系统提示，处理后重跑）")")
        }
        print("")
    }

    // MARK: - 模式一：按键行为 + 独占

    private static func runKeyMode() {
        let state = State()

        // 被动事件监听：只为看 macOS 收到了什么。listenOnly 不改变事件流。
        let tap = installListenOnlyTap(into: state)
        if tap == nil {
            print("⚠️  无法建立事件监听（缺辅助功能权限）。")
            print("   仍会继续测 HID 独占，但「系统是否还收到按键」这一项无法判定。")
            print("")
        }

        let hid = makeManager(state: state)

        print("── A 阶段：独占前（30 秒）──")
        print("请按顺序按一遍遥控器按键：上 下 左 右 确认 返回 主页 菜单 TV 音量+ 音量- 语音")
        print("重点观察：每个键在 macOS 眼里是什么（键码 / 修饰键 / 媒体事件）。")
        print("")
        countdown(30)

        let beforeCount = state.events.count
        print("A 阶段收到 \(beforeCount) 条系统事件：")
        for line in state.events { print("   \(line)") }
        print("")

        // ── B 阶段：独占 ──
        print("── B 阶段：独占（60 秒）──")
        let options = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
        let managerStatus = IOHIDManagerOpen(hid, options)
        print("IOHIDManagerOpen(seize) → \(describe(managerStatus))")

        // 权威判据是逐设备的 IOHIDDeviceOpen：manager 打开成功不代表真的拿到了设备。
        var deviceStatus: IOReturn = kIOReturnSuccess
        var deviceCount = 0
        if let devices = IOHIDManagerCopyDevices(hid) as? Set<IOHIDDevice> {
            deviceCount = devices.count
            for device in devices {
                let status = IOHIDDeviceOpen(device, options)
                print("IOHIDDeviceOpen(seize) → \(describe(status))")
                if status != kIOReturnSuccess { deviceStatus = status }
            }
        }
        print("匹配到设备数：\(deviceCount)")

        let seized = managerStatus == kIOReturnSuccess
            && deviceStatus == kIOReturnSuccess
            && deviceCount > 0
        print("")
        if seized {
            print("✅ 独占成功。再次按一遍所有按键，观察：")
            print("   1. 系统事件监听是否还看得到（看得到 = 独占没生效 = 闸门不通过）")
            print("   2. HID 回调是否仍在收到（收不到 = 按键彻底失联 = 闸门不通过）")
        } else {
            print("❌ 独占失败。这就是 go/no-go 闸门不通过，按键映射不能按接管模型做。")
            print("   常见原因：kIOReturnExclusiveAccess（系统已持有）/ kIOReturnNotPermitted（缺权限）")
        }
        print("")

        state.add("── 以下是 B 阶段 ──")
        let markIndex = state.events.count
        countdown(60)

        let duringEvents = Array(state.events.dropFirst(markIndex))
        print("")
        print("B 阶段系统收到 \(duringEvents.count) 条事件：")
        for line in duringEvents { print("   \(line)") }
        print("")
        print("B 阶段是否发生设备移除：\(state.deviceRemoved ? "是 ← 危险，HOGP 链路被断" : "否")")
        print("")

        // ── C 阶段：释放 ──
        print("── C 阶段：释放独占 ──")
        if let devices = IOHIDManagerCopyDevices(hid) as? Set<IOHIDDevice> {
            for device in devices { IOHIDDeviceClose(device, options) }
        }
        IOHIDManagerClose(hid, options)
        print("已释放。请再按几个键，确认系统恢复响应（回到独占前的行为）。")
        countdown(15)

        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }

        print("")
        print("═══════ 结论 ═══════")
        print("独占成功：\(seized ? "是" : "否")")
        print("独占期间系统仍收到事件：\(duringEvents.isEmpty ? "否（正确抑制）" : "是（未抑制，闸门不通过）")")
        print("独占期间设备被移除：\(state.deviceRemoved ? "是（闸门不通过）" : "否")")
        print("")
        print("把 A 阶段的按键清单抄进 Sources/MiVibeCore/Input/HIDKeyCode.swift 的注释里——")
        print("那张表必须来自实测，不能凭记忆写。")
    }

    // MARK: - 模式二：独占 + 语音通道

    private static func runVoiceMode() {
        print("测的是：独占 HID 之后，BLE 语音通道是否还活着。")
        print("请在 90 秒内按住语音键说话两次（每次约 2 秒，中间松开）。")
        print("")

        let state = State()
        let hid = makeManager(state: state)
        let options = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)

        let status = IOHIDManagerOpen(hid, options)
        print("IOHIDManagerOpen(seize) → \(describe(status))")
        var perDevice: IOReturn = kIOReturnSuccess
        if let devices = IOHIDManagerCopyDevices(hid) as? Set<IOHIDDevice> {
            for device in devices { perDevice = IOHIDDeviceOpen(device, options) }
            print("匹配到设备数：\(devices.count)")
        }
        print("逐设备结果：\(describe(perDevice))")
        print("")

        // 语音通道：RemoteManager 是独立走 CoreBluetooth 的。
        let remote = RemoteManager()
        var starts = 0
        var frames = 0
        var stops = 0

        remote.onRecordingStart = {
            starts += 1
            print("   ▶ AUDIO_START（第 \(starts) 次）")
        }
        remote.onAudioChunk = { pcm in frames += 1 }
        remote.onRecordingFinish = { recording in
            stops += 1
            print("   ■ AUDIO_STOP（第 \(stops) 次）：\(recording.frameCount) 帧，PCM \(recording.pcm.count) 字节")
        }
        remote.connect()

        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        if let devices = IOHIDManagerCopyDevices(hid) as? Set<IOHIDDevice> {
            for device in devices { IOHIDDeviceClose(device, options) }
        }
        IOHIDManagerClose(hid, options)

        print("")
        print("═══════ 结论 ═══════")
        print("AUDIO_START \(starts) 次 / 音频帧 \(frames) / AUDIO_STOP \(stops) 次")
        if starts >= 2 && frames > 0 {
            print("✅ 独占 HID 不影响 BLE 语音通道——接管模型可行。")
        } else {
            print("❌ 独占期间语音通道没收到完整数据——接管模型不可行，需要另想办法。")
        }
    }

    // MARK: - 设施

    private static func makeManager(state: State) -> IOHIDManager {
        let hid = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(hid, [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID,
        ] as CFDictionary)

        let context = Unmanaged.passUnretained(state).toOpaque()

        IOHIDManagerRegisterInputValueCallback(hid, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let state = Unmanaged<State>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == 0x07 else { return }
            let usage = IOHIDElementGetUsage(element)
            guard usage != 0xFFFF_FFFF else { return }
            let isDown = IOHIDValueGetIntegerValue(value) != 0
            let name = RemoteButton(rawValue: usage)?.displayName ?? "未知"
            state.add("HID  \(name) usage=0x\(String(usage, radix: 16)) \(isDown ? "按下" : "抬起")")
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(hid, { context, _, _, _ in
            guard let context else { return }
            let state = Unmanaged<State>.fromOpaque(context).takeUnretainedValue()
            state.markRemoved()
            print("   ⚠️  设备被移除（HOGP 链路可能断了）")
        }, context)

        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return hid
    }

    /// 只监听、不改事件流的事件监听器。用来回答"macOS 到底有没有收到这个键"。
    private static func installListenOnlyTap(into state: State) -> CFMachPort? {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let context = Unmanaged.passUnretained(state).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let state = Unmanaged<State>.fromOpaque(context).takeUnretainedValue()
                let type = event.type
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags

                switch type {
                case .keyDown, .keyUp:
                    let label = Shortcut.keyLabel(UInt16(clamping: keyCode))
                    state.add("系统 \(type == .keyDown ? "按下" : "抬起") 键码=\(keyCode)（\(label)）修饰=\(Shortcut.modifierSymbols(from: flags))")
                case .flagsChanged:
                    state.add("系统 修饰键变化 \(Shortcut.modifierSymbols(from: flags))")
                default:
                    break
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else { return nil }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return tap
    }

    private static func countdown(_ seconds: Double) {
        var remaining = Int(seconds)
        while remaining > 0 {
            print("   剩余 \(remaining)s …（按 Ctrl-C 中止）")
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(1))
            remaining -= 1
        }
    }

    private static func describe(_ status: IOReturn) -> String {
        let name: String
        switch status {
        case kIOReturnSuccess: name = "kIOReturnSuccess"
        case kIOReturnExclusiveAccess: name = "kIOReturnExclusiveAccess（设备已被别人独占）"
        case kIOReturnNotPermitted: name = "kIOReturnNotPermitted（权限不足）"
        case kIOReturnUnsupported: name = "kIOReturnUnsupported（设备不支持）"
        case kIOReturnNotOpen: name = "kIOReturnNotOpen"
        case kIOReturnNoDevice: name = "kIOReturnNoDevice"
        default: name = "其它"
        }
        return "\(name)（0x\(String(format: "%08X", UInt32(bitPattern: status)))）"
    }
}
