import AppKit

/// 按 bundle id 解析应用名称与图标、列出可添加的应用——设置页各处的唯一入口。
enum AppIdentity {
    /// 菜单项图标边长（NSMenu 按图片原始尺寸绘制，应用图标须先缩到菜单行高）。
    private static let menuIconSize = NSSize(width: 16, height: 16)

    /// 应用显示名：在运行的直接取名；没在运行的按 bundle id 找已安装应用，
    /// 用文件系统的展示名（不带 .app 后缀）；都找不到才退回裸 bundle id。
    static func name(for bundleID: String) -> String {
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })?.localizedName {
            return running
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    /// 应用图标：装过的应用取真实图标，否则为 nil（调用方自行占位）。
    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// 缩到菜单行高的图标副本（不改动共享的原图对象）。
    static func menuIcon(for bundleID: String) -> NSImage? {
        guard let original = icon(for: bundleID)?.copy() as? NSImage else { return nil }
        original.size = menuIconSize
        return original
    }

    /// 按显示名排序的 bundle id 列表。
    static func sortedByName(_ bundleIDs: some Sequence<String>) -> [String] {
        bundleIDs.map { (id: $0, name: name(for: $0)) }
            .sorted { $0.name < $1.name }
            .map(\.id)
    }

    /// 可添加覆盖的应用：正在运行的常规应用，排除自己。
    static var runningCandidates: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.bundleIdentifier != nil
                    && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}
