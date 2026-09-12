import ApplicationServices
import AppKit

/// 权限预检（SPEC §5）。
///
/// 只检查文本注入真正需要的两项：辅助功能与事件投递。不申请屏幕录制、
/// 自动化或全局键盘监听。
enum Permissions {
    /// 辅助功能是否已授权。`prompt: true` 会异步弹系统提示——
    /// 弹出不等于已授权，之后仍要重新查询。
    static func hasAccessibility(prompt: Bool = false) -> Bool {
        // 直接用字符串常量：`kAXTrustedCheckOptionPrompt` 是全局 var，
        // Swift 6 并发检查会拒绝引用它。
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 事件投递（粘贴走 Cmd+V 需要）。
    static func hasEventPosting() -> Bool {
        CGPreflightPostEventAccess()
    }

    /// 请求事件投递权限（系统弹窗，异步生效）。
    static func requestEventPosting() {
        _ = CGRequestPostEventAccess()
    }

    static var allGranted: Bool {
        hasAccessibility() && hasEventPosting()
    }

    /// 打开「隐私与安全性 → 辅助功能」设置面板。
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openBluetoothSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth")!
        NSWorkspace.shared.open(url)
    }
}
