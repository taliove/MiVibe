import Cocoa
import CoreBluetooth
import IOKit.hid
import Darwin

final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var manager: CBCentralManager!
    var peripheral: CBPeripheral?
    var tx: CBCharacteristic?
    var rx: CBCharacteristic?
    var control: CBCharacteristic?
    var requested = false
    var ready = false
    var recording = false
    var stream: UInt8 = 0
    var events: [[String: Any]] = []
    var frames = 0
    var done = false
    let output = URL(fileURLWithPath: "/tmp/mivibe-voice-events.json")
    func write(_ bytes: [UInt8]) {
        guard let p = peripheral, let tx else { return }
        p.writeValue(Data(bytes), for: tx, type: tx.properties.contains(.write) ? .withResponse : .withoutResponse)
        print("TX=" + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
    }
    let service = CBUUID(string: "AB5E0001-5A21-4F05-BC7D-AF01F617B664")
    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("BLUETOOTH_STATE=\(central.state.rawValue)")
        guard central.state == .poweredOn else { return }
        let known = central.retrieveConnectedPeripherals(withServices: [service])
        let matches = known.filter { ($0.name ?? "").contains("小米") }
        print("ATVV_CONNECTED_XIAOMI=\(matches.count)")
        if matches.count == 1 { connect(matches[0]) }
        else if matches.isEmpty { central.scanForPeripherals(withServices: [service]) }
        else { print("AMBIGUOUS_DEVICE; no connection attempted") }
    }
    func connect(_ p: CBPeripheral) {
        guard peripheral == nil else { return }
        peripheral = p
        manager.stopScan()
        p.delegate = self
        print("CONNECTING_XIAOMI")
        manager.connect(p)
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard (p.name ?? "").contains("小米") else { return }
        connect(p)
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        print("CONNECTED; discovering ATVV only")
        p.discoverServices([service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { print("CONNECT_FAILED=\(String(describing:error))") }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { print("SERVICE_ERROR=\(error)"); return }
        for s in p.services ?? [] {
            print("SERVICE=\(s.uuid)")
            p.discoverCharacteristics(nil, for: s)
        }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        if let error { print("CHARACTERISTIC_ERROR=\(error)"); return }
        for c in s.characteristics ?? [] { print("CHARACTERISTIC=\(c.uuid) PROPERTIES=\(c.properties.rawValue)") }
        for c in s.characteristics ?? [] {
            if c.uuid.uuidString.hasPrefix("AB5E0002") { tx = c }
            if c.uuid.uuidString.hasPrefix("AB5E0003") { rx = c; p.setNotifyValue(true, for: c) }
            if c.uuid.uuidString.hasPrefix("AB5E0004") { control = c; p.setNotifyValue(true, for: c) }
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        if let error { print("NOTIFY_ERROR=\(error)"); finish(); return }
        if rx?.isNotifying == true && control?.isNotifying == true && !requested {
            requested = true
            write([0x0A,0x01,0x00,0x00,0x03,0x03])
        }
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        if let error { print("WRITE_ERROR=\(error)"); finish() }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard error == nil, let data = c.value, !done else { return }
        let bytes = [UInt8](data)
        let kind = c.uuid == control?.uuid ? "control" : "audio"
        events.append(["time":ProcessInfo.processInfo.systemUptime,"kind":kind,"hex":bytes.map { String(format:"%02X",$0) }.joined()])
        if kind == "audio" {
            frames += 1
            if frames == 1 || frames % 50 == 0 { print("AUDIO_FRAMES=\(frames) BYTES=\(bytes.count)") }
            return
        }
        print("CONTROL=" + bytes.map { String(format:"%02X",$0) }.joined(separator:" "))
        guard let op = bytes.first else { return }
        if op == 0x0B {
            let observed2671Layout = bytes == [0x0B,0x01,0x00,0x00,0x03,0x00,0x78,0x00,0x00]
            guard bytes.count >= 7, bytes[1] == 1, bytes[2] == 0, (bytes[3] & 2 != 0 || observed2671Layout) else {
                print("UNSUPPORTED_CAPABILITIES; no mic open"); finish(); return
            }
            if observed2671Layout { print("KNOWN_2671_CAPS_LAYOUT; codec must be verified by AUDIO_START") }
            ready = true
            print("READY_FOR_ONE_TEST; press voice key and speak up to 6 seconds")
        } else if op == 0x08 && ready && !recording {
            recording = true
            write([0x0C,0x00])
            DispatchQueue.main.asyncAfter(deadline:.now()+8) {
                if !self.done { self.write([0x0D,self.stream]); print("RECORDING_LIMIT") }
            }
        } else if op == 0x04 && bytes.count >= 4 {
            guard bytes[2] == 2 else { print("UNEXPECTED_CODEC"); finish(); return }
            if !recording {
                recording = true
                DispatchQueue.main.asyncAfter(deadline:.now()+8) {
                    if !self.done { self.write([0x0D,self.stream]); print("RECORDING_LIMIT") }
                }
            }
            stream = bytes[3]
            print("AUDIO_STARTED_CODEC=\(bytes[2])")
        } else if op == 0x00 && recording {
            print("AUDIO_STOP; preserving received tail")
            DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { self.finish() }
        }
    }
    func finish() {
        guard !done else { return }
        done = true
        if recording { write([0x0D,stream]) }
        do {
            let data = try JSONSerialization.data(withJSONObject: events, options: [.sortedKeys])
            try data.write(to: output, options:.atomic)
            chmod(output.path, 0o600)
            print("SAVED_LOCAL_EVENTS=\(output.path) AUDIO_FRAMES=\(frames)")
        } catch { print("SAVE_FAILED=\(error)") }
        manager.stopScan()
        if let peripheral { manager.cancelPeripheralConnection(peripheral) }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { NSApplication.shared.terminate(nil) }
    }
}
setbuf(stdout,nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let probe = Probe()
let hid = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(hid, [kIOHIDVendorIDKey:0x2717,kIOHIDProductIDKey:0x32B8] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(hid, { _, result, _, value in
    let element = IOHIDValueGetElement(value)
    guard result == 0, IOHIDElementGetUsagePage(element) == 7, IOHIDElementGetUsage(element) == 0x3E else { return }
    let down = IOHIDValueGetIntegerValue(value) != 0
    print("VOICE_HID=\(down ? "DOWN" : "UP") t=\(ProcessInfo.processInfo.systemUptime)")
    probe.events.append(["kind":"hid", "time":ProcessInfo.processInfo.systemUptime,"hex":down ? "01" : "00"])
    if down && probe.ready && !probe.recording && !probe.done {
        probe.recording = true
        probe.write([0x0C,0x00])
        DispatchQueue.main.asyncAfter(deadline:.now()+8) {
            if !probe.done { probe.write([0x0D,probe.stream]); print("RECORDING_LIMIT") }
        }
    }
},nil)
IOHIDManagerScheduleWithRunLoop(hid,CFRunLoopGetCurrent(),CFRunLoopMode.defaultMode.rawValue)
print("HID_OPEN=\(IOHIDManagerOpen(hid,0))")
DispatchQueue.main.asyncAfter(deadline:.now()+90) { print("DISCOVERY_TIMEOUT"); probe.finish() }
app.run()

IOHIDManagerClose(hid,0)
