import Foundation
import IOKit.hid

/// 遥控器实体按键读取（SPEC §2）。
///
/// 两种打开方式：
/// - **仅监听**（默认）：非独占打开，系统照常处理这些标准 HID 键盘事件，
///   这里只是旁听，用于返回键取消等动作。
/// - **接管**（`takeover: true`）：以 `kIOHIDOptionsTypeSeizeDevice` 独占打开，
///   系统不再翻译报文，所有按键经 `KeyRouter` 裁决后由 `KeySynth` 重新发出。
///
/// 独占是**持续争取**的，不是启动时一次性裁决：BLE 遥控器的连接晚于 App 启动是
/// 常态，启动时 `IOHIDManagerCopyDevices` 多半为空。所以设备每次出现（匹配回调）
/// 都重新尝试 seize，拿到才算数；拿不到之前按键照常仅监听，功能降级但不失联。
public final class KeyReader {
    public static let vendorID = 0x2717
    public static let productID = 0x32B8

    private static let seizeOptions = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)

    /// 实测确认的按键。身份定义在 `RemoteButton`（纯逻辑，可脱离硬件测试）——
    /// 这里只做别名，`KeyReader.Key.up` 这样的写法继续可用。
    public typealias Key = RemoteButton

    /// 按下/抬起回调。主线程投递。第三参是 isRepeat：同一个键没抬起就再次按下。
    /// 实测本机遥控器不自动重复（按住语音键 1.95 秒只有一对 down/up），
    /// 这个标记是防御性的——路由层靠它保证 ⌘Z 不会连发。
    public var onKey: (@MainActor (Key, Bool, Bool) -> Void)?

    /// 独占状态变化回调（拿到/失去独占时触发，参数为是否已独占）。
    public var onExclusiveChanged: (@MainActor (Bool) -> Void)?

    /// 接管（独占）硬失败回调（manager 级打开失败，极少见），参数是给人看的原因。
    public var onTakeoverFailed: (@MainActor (String) -> Void)?

    /// 当前是否独占着设备。false 时系统仍在处理原生按键，
    /// 调用方绝不能自行合成/转发，否则每个键都会发生两次。
    public private(set) var isExclusive = false

    private var manager: IOHIDManager?
    /// 用户意图：要不要独占。与实际是否拿到（`isExclusive`）分开——
    /// 设备迟到、被系统暂持都是暂时的，意图不变，持续重试。
    private var wantExclusive = false
    /// 已独占成功的设备（按对象身份）。BLE 重连后出现的是新对象，需要重新 seize。
    private var seizedDevices: [ObjectIdentifier: IOHIDDevice] = [:]
    /// 当前按住的键：同一个键未抬起又收到按下 → isRepeat。
    private var held: Set<RemoteButton> = []

    public init() {}

    public func start(takeover: Bool = false) {
        guard manager == nil else { return }
        wantExclusive = takeover
        held.removeAll()
        let hid = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(hid, [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
        ] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(hid, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let reader = Unmanaged<KeyReader>.fromOpaque(context).takeUnretainedValue()
            reader.handle(value)
        }, context)

        // BLE 遥控器的断开重连是日常（SPEC §3）：设备每次出现都尝试 seize。
        IOHIDManagerRegisterDeviceMatchingCallback(hid, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<KeyReader>.fromOpaque(context).takeUnretainedValue()
            reader.seize(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hid, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<KeyReader>.fromOpaque(context).takeUnretainedValue()
            reader.unseize(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let options = takeover ? Self.seizeOptions : 0
        let status = IOHIDManagerOpen(hid, options)
        if takeover && status != kIOReturnSuccess {
            // manager 级失败（权限不足等）：退回仅监听。设备到达回调仍会触发重试。
            IOHIDManagerClose(hid, options)
            IOHIDManagerOpen(hid, 0)
            let reason = "HID 打开被拒（\(Self.hex(status))，需要「输入监控」权限）"
            Log.chain.error("takeover failed: \(reason, privacy: .public)")
            Task { @MainActor [onTakeoverFailed] in onTakeoverFailed?(reason) }
        }
        manager = hid
        seizeAllMatched()
    }

    public func stop() {
        guard let manager else { return }
        IOHIDManagerClose(manager, wantExclusive ? Self.seizeOptions : 0)
        self.manager = nil
        wantExclusive = false
        seizedDevices.removeAll()
        held.removeAll()
        if isExclusive {
            isExclusive = false
            notifyExclusiveChanged()
        }
    }

    // MARK: - 独占管理

    /// 对当前匹配到的所有设备尝试 seize。
    private func seizeAllMatched() {
        guard wantExclusive, let manager,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        else { return }
        for device in devices { seize(device) }
    }

    private func seize(_ device: IOHIDDevice) {
        guard wantExclusive else { return }
        let id = ObjectIdentifier(device)
        guard seizedDevices[id] == nil else { return }
        let status = IOHIDDeviceOpen(device, Self.seizeOptions)
        if status == kIOReturnSuccess {
            seizedDevices[id] = device
            Log.chain.notice("seized HID device (\(self.seizedDevices.count) held)")
        } else {
            Log.chain.error("seize failed: \(Self.hex(status), privacy: .public)")
        }
        updateExclusive()
    }

    /// IOReturn 是有符号 Int32，`String(radix:)` 对负数会输出 "0x-1ffffd3f" 这种
    /// 没法查的格式；按位解释为 UInt32 才是文档里的 0xE00002C1。
    static func hex(_ status: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: status))
    }

    private func unseize(_ device: IOHIDDevice) {
        seizedDevices.removeValue(forKey: ObjectIdentifier(device))
        updateExclusive()
    }

    private func updateExclusive() {
        let now = !seizedDevices.isEmpty
        guard now != isExclusive else { return }
        isExclusive = now
        Log.chain.notice("takeover now \(now ? "active" : "inactive", privacy: .public)")
        notifyExclusiveChanged()
    }

    private func notifyExclusiveChanged() {
        let value = isExclusive
        Task { @MainActor [onExclusiveChanged] in onExclusiveChanged?(value) }
    }

    // MARK: - 按键事件

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == 0x07 else { return }
        let usage = IOHIDElementGetUsage(element)
        // 0xFFFFFFFF 是数组占位元素，不是实体按键（实测）。
        guard usage != 0xFFFF_FFFF, let key = Key(rawValue: usage) else { return }

        let isDown = IOHIDValueGetIntegerValue(value) != 0
        let isRepeat: Bool
        if isDown {
            isRepeat = held.contains(key)
            held.insert(key)
        } else {
            isRepeat = false
            held.remove(key)
        }
        // 回调已标注 @MainActor：HID 回调虽在主 run loop 上触发，
        // 仍显式跳一次以满足并发检查。
        Task { @MainActor [onKey] in onKey?(key, isDown, isRepeat) }
    }
}
