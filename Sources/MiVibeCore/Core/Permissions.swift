import ApplicationServices
import AppKit
import IOKit.hid

/// 权限预检（SPEC §5）。
///
/// 文本注入需要两项：辅助功能与事件投递。按键接管（HID 独占）另需
/// 「输入监控」。不申请屏幕录制、自动化。
public enum Permissions {
    /// 辅助功能是否已授权。`prompt: true` 会异步弹系统提示——
    /// 弹出不等于已授权，之后仍要重新查询。
    public static func hasAccessibility(prompt: Bool = false) -> Bool {
        // 直接用字符串常量：`kAXTrustedCheckOptionPrompt` 是全局 var，
        // Swift 6 并发检查会拒绝引用它。
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 事件投递（粘贴走 Cmd+V 需要）。
    public static func hasEventPosting() -> Bool {
        CGPreflightPostEventAccess()
    }

    /// 请求事件投递权限（系统弹窗，异步生效）。
    public static func requestEventPosting() {
        _ = CGRequestPostEventAccess()
    }

    /// 输入监控（HID 独占接管需要）。`request: true` 未决定时弹系统提示。
    public static func hasInputMonitoring() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// 请求输入监控权限。返回是否已授权（可能刚弹了系统提示，用户处理后需重查）。
    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public static var allGranted: Bool {
        hasAccessibility() && hasEventPosting()
    }

    /// 打开「隐私与安全性 → 辅助功能」设置面板。
    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    public static func openBluetoothSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth")!
        NSWorkspace.shared.open(url)
    }

    /// 打开「隐私与安全性 → 输入监控」设置面板。
    public static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
