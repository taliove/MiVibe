import Cocoa
import ApplicationServices

// MiVibe 注入探针（10 票）：对前台应用的焦点输入框实测两条注入路径。
//   ax    — AXSelectedText 写入（定点插入，不碰剪贴板）
//   paste — 剪贴板快照 + Cmd+V 定向投递 + 尝试恢复剪贴板
//   check — 只报告权限与焦点元素形态，不注入
// 用法：inject-probe <check|ax|paste> [倒计时秒=6]
// 流程：倒计时内用户点击目标输入框 → 探针锁定前台应用并注入带唯一标记的测试串 →
//       读回验证并输出 JSON 证据行。不发送 Return，不自动重试。
// 注意：需要辅助功能权限（首次运行系统会弹授权）；事件投递权限不足时 paste 会失败并如实报告。

struct Evidence: Codable {
    var strategy: String
    var app: String
    var pid: Int32
    var role: String?
    var subrole: String?
    var valueSettable: Bool?
    var selectedTextSettable: Bool?
    var injected: String
    var verified: Bool
    var method: String
    var note: String
}

func axValue<T>(_ el: AXUIElement, _ attr: String, as type: T.Type) -> T? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
    return ref as? T
}

func settable(_ el: AXUIElement, _ attr: String) -> Bool {
    var flag = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(el, attr as CFString, &flag) == .success else { return false }
    return flag.boolValue
}

func emit(_ e: Evidence) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    if let d = try? enc.encode(e), let s = String(data: d, encoding: .utf8) {
        print("EVIDENCE " + s)
        let path = "/tmp/mivibe-inject-evidence.jsonl"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile(); fh.write((s + "\n").data(using: .utf8)!); fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: (s + "\n").data(using: .utf8))
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }
}

let args = CommandLine.arguments
let strategy = args.count > 1 ? args[1] : "check"
let countdown = args.count > 2 ? Double(args[2]) ?? 6 : 6
guard ["check", "ax", "paste"].contains(strategy) else {
    print("usage: inject-probe <check|ax|paste> [countdown]"); exit(2)
}

// 权限：不弹窗预检；缺失时打印指引并退出（由用户决定何时授权）。
let trusted = AXIsProcessTrustedWithOptions(nil)
print("AX_TRUSTED=\(trusted)")
let eventAccess = CGPreflightPostEventAccess()
print("EVENT_POST_ACCESS=\(eventAccess)")
if strategy == "check" && !trusted {
    print("NEED_AX_PERMISSION: 系统设置 → 隐私与安全性 → 辅助功能 → 允许运行本探针的终端")
}

print("请在 \(Int(countdown)) 秒内点击目标应用的输入框…")
Thread.sleep(forTimeInterval: countdown)

guard let front = NSWorkspace.shared.frontmostApplication else {
    print("NO_FRONTMOST_APP"); exit(1)
}
let pid = front.processIdentifier
let appName = front.localizedName ?? "?"
print("TARGET_APP=\(appName) PID=\(pid)")
if pid == ProcessInfo.processInfo.processIdentifier {
    print("REFUSE: 目标是自己"); exit(1)
}

let appEl = AXUIElementCreateApplication(pid)
guard trusted, let focused = axValue(appEl, kAXFocusedUIElementAttribute, as: AXUIElement.self) else {
    emit(Evidence(strategy: strategy, app: appName, pid: pid, role: nil, subrole: nil,
                  valueSettable: nil, selectedTextSettable: nil,
                  injected: "", verified: false, method: "none",
                  note: "无 AX 权限或无焦点元素"))
    exit(1)
}

let role = axValue(focused, kAXRoleAttribute, as: String.self)
let subrole = axValue(focused, kAXSubroleAttribute, as: String.self)
let valueOk = settable(focused, kAXValueAttribute)
let selOk = settable(focused, kAXSelectedTextAttribute)
print("ROLE=\(role ?? "?") SUBROLE=\(subrole ?? "-") AXValue可写=\(valueOk) AXSelectedText可写=\(selOk)")

let marker = "mivibe测试🎤\(Int.random(in: 1000...9999))"

if strategy == "check" {
    emit(Evidence(strategy: strategy, app: appName, pid: pid, role: role, subrole: subrole,
                  valueSettable: valueOk, selectedTextSettable: selOk,
                  injected: "", verified: false, method: "none", note: "仅探测"))
    exit(0)
}

// 安全输入框排除：subrole 含 Secure 直接拒绝
if (subrole ?? "").contains("Secure") {
    emit(Evidence(strategy: strategy, app: appName, pid: pid, role: role, subrole: subrole,
                  valueSettable: valueOk, selectedTextSettable: selOk,
                  injected: "", verified: false, method: "refused",
                  note: "安全输入框，按 03 票边界拒绝注入"))
    exit(3)
}

if strategy == "ax" {
    guard selOk else {
        emit(Evidence(strategy: strategy, app: appName, pid: pid, role: role, subrole: subrole,
                      valueSettable: valueOk, selectedTextSettable: selOk,
                      injected: "", verified: false, method: "ax",
                      note: "AXSelectedText 不可写，该路径不适用"))
        exit(4)
    }
    let err = AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, marker as CFString)
    // 验证：读回全文找唯一标记（仅验证用，非常规行为）
    Thread.sleep(forTimeInterval: 0.3)
    let after = axValue(focused, kAXValueAttribute, as: String.self) ?? ""
    let ok = err == .success && after.contains(marker)
    emit(Evidence(strategy: strategy, app: appName, pid: pid, role: role, subrole: subrole,
                  valueSettable: valueOk, selectedTextSettable: selOk,
                  injected: marker, verified: ok, method: "ax",
                  note: err == .success ? (ok ? "读回验证通过" : "写入返回成功但读回未见标记") : "AXError=\(err.rawValue)"))
    print(ok ? "AX_INJECT_OK" : "AX_INJECT_UNVERIFIED")
    exit(ok ? 0 : 5)
}

// paste 策略
guard eventAccess else {
    emit(Evidence(strategy: strategy, app: appName, pid: pid, role: role, subrole: subrole,
                  valueSettable: valueOk, selectedTextSettable: selOk,
                  injected: "", verified: false, method: "paste",
                  note: "缺少事件投递权限"))
    exit(6)
}
let pb = NSPasteboard.general
let beforeChange = pb.changeCount
let snapshot: [(NSPasteboard.PasteboardType, Data)] = (pb.pasteboardItems ?? []).flatMap { item in
    item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
}
pb.clearContents()
pb.setString(marker, forType: .string)
let ourChange = pb.changeCount

let src = CGEventSource(stateID: .hidSystemState)
if let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
   let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) {
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.postToPid(pid)
    up.postToPid(pid)
}
Thread.sleep(forTimeInterval: 0.6)
let after = axValue(focused, kAXValueAttribute, as: String.self) ?? ""
let ok = after.contains(marker)

// 恢复剪贴板：仅当期间没有第三方改动；多类型并入单 item 恢复（探针级近似，非无损承诺）
var restored = false
if pb.changeCount == ourChange {
    pb.clearContents()
    if !snapshot.isEmpty {
        let item = NSPasteboardItem()
        for (t, d) in snapshot { item.setData(d, forType: t) }
        pb.writeObjects([item])
        restored = true
    }
} else {
    print("PASTEBOARD_DIRTY: 期间被第三方改动，放弃恢复")
}
emit(Evidence(strategy: strategy, app: appName, pid: pid, role: role, subrole: subrole,
              valueSettable: valueOk, selectedTextSettable: selOk,
              injected: marker, verified: ok, method: "paste",
              note: "changeCount \(beforeChange)->\(ourChange) 恢复=\(restored)"))
print(ok ? "PASTE_INJECT_OK" : "PASTE_INJECT_UNVERIFIED")
exit(ok ? 0 : 5)
