import Foundation
import IOKit.hid

/// 遥控器实体按键读取（SPEC §2）。
///
/// 两种打开方式：
/// - **仅监听**（默认）：非独占打开，系统照常处理这些标准 HID 键盘事件，
///   这里只是旁听，用于返回键取消等动作。
/// - **接管**（`takeover: true`）：以 `kIOHIDOptionsTypeSeizeDevice` 独占打开，
///   系统不再翻译报文，所有按键经 `KeyRouter` 裁决后由 `KeySynth` 重新发出。
///   独占失败（权限不足/设备已被持有）时自动回退仅监听，并通过
///   `onTakeoverFailed` 告知——宁可功能降级，不让遥控器彻底失联。
public final class KeyReader {
    public static let vendorID = 0x2717
    public static let productID = 0x32B8

    /// 实测确认的按键。身份定义在 `RemoteButton`（纯逻辑，可脱离硬件测试）——
    /// 这里只做别名，`KeyReader.Key.up` 这样的写法继续可用。
    public typealias Key = RemoteButton

    /// 按下/抬起回调。主线程投递。第三参是 isRepeat：同一个键没抬起就再次按下。
    /// 实测本机遥控器不自动重复（按住语音键 1.95 秒只有一对 down/up），
    /// 这个标记是防御性的——路由层靠它保证 ⌘Z 不会连发。
    public var onKey: (@MainActor (Key, Bool, Bool) -> Void)?

    /// 接管（独占）失败回调，参数是给人看的原因说明。失败后已自动回退仅监听。
    public var onTakeoverFailed: (@MainActor (String) -> Void)?

    /// 当前是否独占着设备。false 时系统仍在处理原生按键，
    /// 调用方绝不能自行合成/转发，否则每个键都会发生两次。
    public private(set) var isExclusive = false

    private var manager: IOHIDManager?
    /// 当前按住的键：同一个键未抬起又收到按下 → isRepeat。
    private var held: Set<RemoteButton> = []

    public init() {}

    public func start(takeover: Bool = false) {
        guard manager == nil else { return }
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

        // BLE 遥控器的断开重连是日常（SPEC §3）：独占模式下设备重新出现时
        // 必须重新 seize，否则重连之后按键又回到系统手里。
        IOHIDManagerRegisterDeviceMatchingCallback(hid, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<KeyReader>.fromOpaque(context).takeUnretainedValue()
            reader.seizeIfNeeded(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        if takeover {
            let options = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
            let status = IOHIDManagerOpen(hid, options)
            // 权威判据是逐设备打开：manager 打开成功不代表真拿到了设备（SeizeProbe 结论）。
            var seized = status == kIOReturnSuccess
            var found = false
            if let devices = IOHIDManagerCopyDevices(hid) as? Set<IOHIDDevice>, !devices.isEmpty {
                found = true
                for device in devices where IOHIDDeviceOpen(device, options) != kIOReturnSuccess {
                    seized = false
                }
            }
            if seized && found {
                isExclusive = true
            } else {
                // 回退仅监听：按键还能用于返回键取消，只是映射/转发不生效。
                isExclusive = false
                IOHIDManagerClose(hid, options)
                IOHIDManagerOpen(hid, 0)
                let reason = found
                    ? "设备被系统持有或权限不足（需要「输入监控」权限）"
                    : "未找到遥控器"
                Task { @MainActor [onTakeoverFailed] in onTakeoverFailed?(reason) }
            }
        } else {
            IOHIDManagerOpen(hid, 0)
        }
        manager = hid
    }

    public func stop() {
        guard let manager else { return }
        IOHIDManagerClose(manager, isExclusive ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : 0)
        self.manager = nil
        isExclusive = false
        held.removeAll()
    }

    /// 独占模式下 seize 一个刚出现的设备。仅监听模式什么都不做。
    private func seizeIfNeeded(_ device: IOHIDDevice) {
        guard isExclusive else { return }
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    }

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
