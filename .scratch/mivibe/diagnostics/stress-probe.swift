import Cocoa
import CoreBluetooth

// MiVibe 压力恢复探针（09 票）：程序驱动 MIC_OPEN，不需要按遥控器。
// 模式：
//   cycles  — 快速连续录音：5 轮 MIC_OPEN→1.2s 采集→MIC_CLOSE→0.4s 间隔
//   hold    — 打开麦克风后持续采集，不主动关闭（供 kill -9 异常退出测试）
//   button  — 纯监听：不发 MIC_OPEN，等用户按住语音键，统计 5 段按键驱动的录音会话
// 证据：每轮时序/帧数写 /tmp/mivibe-stress-<mode>-<ts>.jsonl（0600，不含音频内容），音频仅计数。
// 运行：swiftc -o /tmp/stress-probe stress-probe.swift && /tmp/stress-probe cycles|hold|button

final class Stress: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var manager: CBCentralManager!
    var peripheral: CBPeripheral?
    var tx: CBCharacteristic?
    var rx: CBCharacteristic?
    var control: CBCharacteristic?
    var requested = false
    var ready = false
    var mode = "cycles"
    var stream: UInt8 = 0
    var cycle = 0
    var cycleStart: TimeInterval = 0
    var micOpenAt: TimeInterval = 0
    var framesThisCycle = 0
    var sessionOpen = false
    var sessionStart: TimeInterval = 0
    var sessionCount = 0
    var awaitingStop = false
    var done = false
    let maxCycles = 5
    let captureSeconds = 1.2
    let gapSeconds = 0.4

    var evidencePath = "/tmp/mivibe-stress-evidence.jsonl"

    let service = CBUUID(string: "AB5E0001-5A21-4F05-BC7D-AF01F617B664")

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func log(_ kind: String, _ data: [String: Any] = [:]) {
        var rec: [String: Any] = ["t": round((now() - cycleStart) * 1000) / 1000, "kind": kind]
        rec.merge(data) { _, new in new }
        if let d = try? JSONSerialization.data(withJSONObject: rec, options: [.sortedKeys]),
           let s = String(data: d, encoding: .utf8) {
            print(s)
            if let fh = FileHandle(forWritingAtPath: evidencePath) {
                fh.seekToEndOfFile(); fh.write((s + "\n").data(using: .utf8)!); fh.closeFile()
            } else {
                FileManager.default.createFile(atPath: evidencePath, contents: (s + "\n").data(using: .utf8))
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: evidencePath)
            }
        }
    }

    func write(_ bytes: [UInt8]) {
        guard let p = peripheral, let tx else { return }
        p.writeValue(Data(bytes), for: tx, type: tx.properties.contains(.write) ? .withResponse : .withoutResponse)
        log("tx", ["hex": bytes.map { String(format: "%02X", $0) }.joined(separator: " ")])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("bluetooth_state", ["state": central.state.rawValue])
        guard central.state == .poweredOn else { return }
        let known = central.retrieveConnectedPeripherals(withServices: [service])
        let matches = known.filter { ($0.name ?? "").contains("小米") }
        if matches.count == 1 { connect(matches[0]) }
        else if matches.isEmpty { central.scanForPeripherals(withServices: [service]) }
        else { log("ambiguous_device"); }
    }

    func connect(_ p: CBPeripheral) {
        guard peripheral == nil else { return }
        peripheral = p
        manager.stopScan()
        p.delegate = self
        log("connecting")
        manager.connect(p)
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard (p.name ?? "").contains("小米") else { return }
        connect(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        log("connected")
        p.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        log("connect_failed", ["error": String(describing: error)])
        finish()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log("disconnected", ["error": error.map { "\($0)" } ?? "none"])
        if !done { finish() }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { log("service_error", ["error": "\(error)"]); finish(); return }
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        if let error { log("char_error", ["error": "\(error)"]); finish(); return }
        for c in s.characteristics ?? [] {
            if c.uuid.uuidString.hasPrefix("AB5E0002") { tx = c }
            if c.uuid.uuidString.hasPrefix("AB5E0003") { rx = c; p.setNotifyValue(true, for: c) }
            if c.uuid.uuidString.hasPrefix("AB5E0004") { control = c; p.setNotifyValue(true, for: c) }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        if let error { log("notify_error", ["error": "\(error)"]); finish(); return }
        if rx?.isNotifying == true && control?.isNotifying == true && !requested {
            requested = true
            write([0x0A, 0x01, 0x00, 0x00, 0x03, 0x03]) // GET_CAPS
        }
    }

    func startCycle() {
        cycle += 1
        framesThisCycle = 0
        micOpenAt = now()
        log("cycle_begin", ["cycle": cycle])
        write([0x0C, 0x00]) // MIC_OPEN
        DispatchQueue.main.asyncAfter(deadline: .now() + captureSeconds) { [weak self] in
            guard let self, !self.done, !self.awaitingStop else { return }
            self.awaitingStop = true
            self.write([0x0D, self.stream]) // MIC_CLOSE
            self.log("mic_close_sent", ["cycle": self.cycle, "frames": self.framesThisCycle])
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard error == nil, let data = c.value, !done else { return }
        let bytes = [UInt8](data)
        if c.uuid == rx?.uuid { framesThisCycle += 1; return } // 音频帧只计数不落盘
        guard let op = bytes.first else { return }
        log("control", ["hex": bytes.map { String(format: "%02X", $0) }.joined(separator: " "), "cycle": cycle])

        if op == 0x0B { // GET_CAPS 响应：标准或固件2671白名单布局
            let observed2671 = bytes == [0x0B, 0x01, 0x00, 0x00, 0x03, 0x00, 0x78, 0x00, 0x00]
            guard bytes.count >= 7, bytes[1] == 1, bytes[2] == 0, (bytes[3] & 2 != 0 || observed2671) else {
                log("unsupported_caps"); finish(); return
            }
            if observed2671 { log("known_2671_caps_layout") }
            ready = true
            log("ready")
            if mode == "hold" {
                micOpenAt = now()
                write([0x0C, 0x00])
                log("hold_mic_open_sent")
            } else if mode == "button" {
                log("button_mode_listening", ["note": "请按住语音键说话1秒松开，快速重复5次"])
            } else {
                startCycle()
            }
        } else if op == 0x04 && bytes.count >= 4 { // AUDIO_START
            guard bytes[2] == 2 else { log("unexpected_codec", ["codec": bytes[2]]); finish(); return }
            stream = bytes[3]
            if mode == "button" {
                if !sessionOpen {
                    sessionOpen = true
                    sessionCount += 1
                    sessionStart = now()
                    framesThisCycle = 0
                    log("button_session_start", ["session": sessionCount, "raw": bytes.map { String(format: "%02X", $0) }.joined()])
                }
            } else if mode == "hold" {
                log("audio_started", ["codec": bytes[2], "latency_ms": Int((now() - micOpenAt) * 1000)])
            } else {
                log("audio_started", ["cycle": cycle, "codec": bytes[2], "latency_ms": Int((now() - micOpenAt) * 1000)])
            }
        } else if op == 0x00 { // AUDIO_STOP
            if mode == "button" {
                if sessionOpen {
                    sessionOpen = false
                    log("button_session_complete", ["session": sessionCount, "frames": framesThisCycle,
                                                   "duration_ms": Int((now() - sessionStart) * 1000)])
                    if sessionCount >= 5 {
                        log("all_button_sessions_complete", ["sessions": sessionCount])
                        finish()
                    }
                } else {
                    log("audio_stop_without_session")
                }
            } else if mode == "hold" {
                log("audio_stop_in_hold")
            } else {
                log("cycle_complete", ["cycle": cycle, "frames": framesThisCycle])
                awaitingStop = false
                if cycle >= maxCycles {
                    log("all_cycles_complete", ["cycles": cycle])
                    finish()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + gapSeconds) { [weak self] in
                        guard let self, !self.done else { return }
                        self.startCycle()
                    }
                }
            }
        } else if op == 0x08 && mode != "hold" {
            log("start_search_ignored_program_driven")
        }
    }

    func finish() {
        guard !done else { return }
        done = true
        manager.stopScan()
        if let peripheral { manager.cancelPeripheralConnection(peripheral) }
        log("finished")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApplication.shared.terminate(nil) }
    }
}

setbuf(stdout, nil)
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "cycles"
guard mode == "cycles" || mode == "hold" || mode == "button" else {
    print("usage: stress-probe cycles|hold|button"); exit(2)
}
let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
let evidencePath = "/tmp/mivibe-stress-\(mode)-\(stamp).jsonl"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let stress = Stress()
stress.mode = mode
stress.evidencePath = evidencePath
stress.cycleStart = ProcessInfo.processInfo.systemUptime
print("EVIDENCE=\(evidencePath) MODE=\(mode)")
DispatchQueue.main.asyncAfter(deadline: .now() + (mode == "button" ? 90 : 60)) {
    print("GLOBAL_TIMEOUT"); stress.finish()
}
app.run()
