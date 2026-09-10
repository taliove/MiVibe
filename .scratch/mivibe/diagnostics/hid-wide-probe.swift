import Cocoa
import IOKit.hid

// MiVibe 宽域 HID 探针（09 票物理测试用）：匹配小米遥控器 VID/PID，
// 不做 usage 过滤，记录所有 page/usage 事件；同时记录系统休眠/唤醒通知。
// 用于：电源键副作用确认、普通按键事件采集、休眠唤醒前后事件对照。
// 运行：swiftc -o /tmp/mivibe-hid-wide hid-wide-probe.swift && /tmp/mivibe-hid-wide [秒数]
// 证据：stdout 重定向，/tmp，0600；不修改任何系统映射。

setbuf(stdout, nil)
let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 120 : 120

final class SleepLogger: NSObject {
    @objc func willSleep(_ n: Notification) {
        print("SYSTEM_WILL_SLEEP t=\(ProcessInfo.processInfo.systemUptime)")
    }
    @objc func didWake(_ n: Notification) {
        print("SYSTEM_DID_WAKE t=\(ProcessInfo.processInfo.systemUptime)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let sleepLogger = SleepLogger()
NSWorkspace.shared.notificationCenter.addObserver(sleepLogger, selector: #selector(SleepLogger.willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
NSWorkspace.shared.notificationCenter.addObserver(sleepLogger, selector: #selector(SleepLogger.didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)

let hid = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(hid, [kIOHIDVendorIDKey: 0x2717, kIOHIDProductIDKey: 0x32B8] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(hid, { _, result, _, value in
    guard result == 0 else { return }
    let el = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(el)
    let usage = IOHIDElementGetUsage(el)
    let intValue = IOHIDValueGetIntegerValue(value)
    // usage=0xFFFFFFFF 是数组占位元素，跳过（与 06 票基线一致）
    guard usage != 0xFFFFFFFF else { return }
    print(String(format: "HID page=0x%02X usage=0x%02X value=%d t=%.3f", page, usage, intValue, ProcessInfo.processInfo.systemUptime))
}, nil)
IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
print("HID_OPEN=\(IOHIDManagerOpen(hid, 0)) WINDOW=\(seconds)s")
print("等待事件：电源键 / 普通按键 / 休眠唤醒都将原样记录")
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    print("WINDOW_CLOSED")
    exit(0)
}
app.run()
IOHIDManagerClose(hid, 0)
