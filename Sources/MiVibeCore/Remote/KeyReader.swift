import Foundation
import IOKit.hid

/// 遥控器实体按键读取（SPEC §2）。
///
/// 非独占方式打开 IOHIDManager，只监听目标 VID/PID，**不修改任何系统映射**。
/// 这些键本身是标准 HID 键盘事件，系统照常处理；这里只是旁听，用于返回键取消等动作。
public final class KeyReader {
    public static let vendorID = 0x2717
    public static let productID = 0x32B8

    /// 实测确认的按键（usage page 0x07）。
    public enum Key: UInt32, CaseIterable {
        case up = 0x52
        case down = 0x51
        case left = 0x50
        case right = 0x4F
        case confirm = 0x28
        case back = 0xF1
        case volumeUp = 0x80
        case volumeDown = 0x81
        case home = 0x4A
        case menu = 0x65
        case tv = 0x35
        case voice = 0x3E
        case power = 0x66   // 本机系统无响应，不接管
    }

    /// 按下/抬起回调。主线程投递。
    public var onKey: (@MainActor (Key, Bool) -> Void)?

    private var manager: IOHIDManager?

    public init() {}

    public func start() {
        guard manager == nil else { return }
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

        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(hid, 0)
        manager = hid
    }

    public func stop() {
        guard let manager else { return }
        IOHIDManagerClose(manager, 0)
        self.manager = nil
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == 0x07 else { return }
        let usage = IOHIDElementGetUsage(element)
        // 0xFFFFFFFF 是数组占位元素，不是实体按键（实测）。
        guard usage != 0xFFFF_FFFF, let key = Key(rawValue: usage) else { return }

        let isDown = IOHIDValueGetIntegerValue(value) != 0
        // 回调已标注 @MainActor：HID 回调虽在主 run loop 上触发，
        // 仍显式跳一次以满足并发检查。
        Task { @MainActor [onKey] in onKey?(key, isDown) }
    }
}
