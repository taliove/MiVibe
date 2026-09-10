import Foundation
import IOKit.hid
import Darwin

setbuf(stdout, nil)
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x2717, kIOHIDProductIDKey: 0x32B8] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(manager, { _, result, _, value in
    guard result == kIOReturnSuccess else { return }
    let element = IOHIDValueGetElement(value)
    print(String(format: "t=%.3f page=0x%04X usage=0x%04X value=%ld", ProcessInfo.processInfo.systemUptime, IOHIDElementGetUsagePage(element), IOHIDElementGetUsage(element), IOHIDValueGetIntegerValue(value)))
}, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
print("OPEN_RESULT=\(result)")
let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
print("MATCHED_DEVICES=\(devices.count)")
for device in devices {
    print("DEVICE=\(IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) ?? "unknown" as CFString)")
}
guard result == kIOReturnSuccess, !devices.isEmpty else { exit(2) }
print("LISTENING_SECONDS=90; target device only; no grabbing or synthesized events")
RunLoop.current.run(until: Date().addingTimeInterval(90))
IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
print("FINISHED")
