import MiVibeCore
import SwiftUI

/// 菜单栏弹窗：状态 + 配对引导 + 待处理内容 + 设置入口（SPEC §7）。
///
/// 结构约定：头部是当前链路状态（连接 + 引擎 + 改写模式），中段按需出现
/// 引导/权限/待处理，底部固定「设置… ⌘,」与「退出 ⌘Q」。引导与权限提示不用
/// 卡片底色——弹窗里内容本就是一个整体，图标 + 加粗标题足够分层。
///
/// 颜色全部走主题令牌（epic #1 子任务 C）：头部品牌块用 accentSoft/accent，
/// 引导与权限标签用 attention，主按钮用 accentFill + onAccentFill 文字。
struct MenuPopover: View {
    @ObservedObject var coordinator: Coordinator
    /// 主题观察：主题切换时弹层立刻重绘（值取自 BrandColorCurrent，不观察则
    /// 颜色对但不重算，见 Brand.swift 头注释）。
    @ObservedObject private var themeStore: ThemeStore

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        self._themeStore = ObservedObject(wrappedValue: AppDelegate.shared.themeStore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if coordinator.link == .unpaired {
                Divider()
                pairingGuide
            }

            if !permissionsOK {
                Divider()
                permissionNotice
            }

            if !coordinator.queue.items.isEmpty {
                Divider()
                pendingItems
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .tint(Color.brandAccent)
    }

    // MARK: - 头部：链路状态

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                brandTile
                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.link.rawValue)
                        .font(.headline)
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            statusRow(title: "识别引擎") { engineMenu }
            statusRow(title: "改写模式") { modeMenu }
        }
    }

    /// 28×28 品牌块（圆角 8）：已连接 = accentSoft 底 + accent 波形标；
    /// 离线/未配对 = attention 16% 底 + 45% 透明度的标。
    private var brandTile: some View {
        let connected = coordinator.link == .connected
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(connected ? Color.brandAccentSoft : Color.brandAttention.opacity(0.16))
            BrandGlyph()
                .frame(width: 18, height: 18)
                .foregroundStyle(connected ? Color.brandAccent : Color.brandAttention.opacity(0.45))
        }
        .frame(width: 28, height: 28)
    }

    /// 副标题：连接态区分按键接管是否生效；离线/未配对给出原因指引（spec C 文案）。
    private var headerSubtitle: String {
        switch coordinator.link {
        case .connected:
            return coordinator.keyTakeoverActive
                ? "小米蓝牙语音遥控器 · 接管生效中"
                : "小米蓝牙语音遥控器 · 按键由系统处理"
        case .pairedOffline:
            return "遥控器未连接"
        case .unpaired:
            return "按说明书让遥控器进入配对状态"
        }
    }

    /// 状态行：左标签右控件，两行对齐一致。
    private func statusRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            content()
        }
    }

    private var engineMenu: some View {
        Menu {
            ForEach(ASREngine.allCases, id: \.self) { engine in
                Button {
                    coordinator.setASREngine(engine)
                } label: {
                    if engine == coordinator.asrEngine {
                        Label(engine.displayName, systemImage: "checkmark")
                    } else {
                        Text(engine.displayName)
                    }
                }
            }
        } label: {
            popupLabel(coordinator.asrEngine.displayName)
        }
        .controlSize(.small)
        .help("点击切换识别引擎")
    }

    private var modeMenu: some View {
        Menu {
            modeEntry(id: RewriteModes.rawID, name: "原文直出")
            ForEach(RewriteModes.builtins) { mode in
                modeEntry(id: mode.id, name: mode.name)
            }
            let custom = coordinator.rewrite.effectiveCustomModes
            if !custom.isEmpty {
                Divider()
                ForEach(custom) { mode in
                    modeEntry(id: mode.id, name: mode.name)
                }
            }
        } label: {
            popupLabel(coordinator.currentModeName)
        }
        .controlSize(.small)
        .help("点击切换改写模式；遥控器菜单键可呼出选单")
    }

    private func modeEntry(id: String, name: String) -> some View {
        Button {
            coordinator.selectMode(id)
        } label: {
            if id == coordinator.rewrite.effectiveActiveMode {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
    }

    /// 仿系统弹出按钮的「当前值 + 上下箭头」外观。
    private func popupLabel(_ value: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 引导与权限

    private var pairingGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("首次配对", systemImage: "exclamationmark.circle.fill")
                .font(.subheadline).bold()
                .foregroundStyle(Color.brandAttention)
            Text("1. 遥控器进入配对状态（详见说明书）\n2. 点击下方「打开蓝牙设置」\n3. 在列表中选择「小米蓝牙语音遥控器」")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("打开蓝牙设置…") { Permissions.openBluetoothSettings() }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandAccentFill)
                .foregroundStyle(Color.brandOnAccentFill)
                .controlSize(.small)
        }
    }

    private var permissionsOK: Bool {
        Permissions.hasAccessibility() && Permissions.hasEventPosting()
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("需要辅助功能权限", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline).bold()
                .foregroundStyle(Color.brandAttention)
            Text("文字要写进别的应用，必须获得「辅助功能」授权。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("打开权限设置…") { Permissions.openAccessibilitySettings() }
                .controlSize(.small)
        }
    }

    // MARK: - 待处理

    private var pendingItems: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("待处理（\(coordinator.queue.items.count)/2）")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(coordinator.queue.items) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(dotColor(QueueDotColor.phase(item.phase)))
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phaseLabel(item.phase))
                            .font(.callout)
                        if let text = phaseText(item.phase) {
                            Text(text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if phaseText(item.phase) != nil {
                        Button("输入到这里") { coordinator.resumeHere(id: item.id) }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.brandAccentFill)
                            .foregroundStyle(Color.brandOnAccentFill)
                            .controlSize(.small)
                    } else if item.phase == .needsAttention(.transcriptionFailed), coordinator.canRetry(id: item.id) {
                        Button("重试") { coordinator.retry(id: item.id) }
                            .controlSize(.small)
                    }
                    Button {
                        coordinator.discard(id: item.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                    .help("丢弃")
                }
                .contextMenu {
                    if phaseText(item.phase) != nil {
                        Button("输入到这里") { coordinator.resumeHere(id: item.id) }
                    }
                    Button("丢弃", role: .destructive) { coordinator.discard(id: item.id) }
                }
            }
        }
    }

    // MARK: - 底部

    private var footer: some View {
        HStack {
            Button("设置…") { AppDelegate.shared.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button("退出") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - 阶段呈现

    private func phaseLabel(_ phase: InputQueue.Phase) -> String {
        switch phase {
        case .listening: return "正在听"
        case .transcribing: return "正在转写"
        case .ready: return "待输入"
        case .needsAttention(.transcriptionFailed): return "转写失败"
        case .needsAttention(.targetLost): return "目标已变，待恢复"
        case .needsAttention(.injectionFailed): return "输入失败"
        }
    }

    private func phaseText(_ phase: InputQueue.Phase) -> String? {
        switch phase {
        case .ready(let text): return text
        case .needsAttention(.targetLost(let text)): return text.isEmpty ? nil : text
        case .needsAttention(.injectionFailed(let text)): return text
        case .listening, .transcribing, .needsAttention(.transcriptionFailed): return nil
        }
    }

    /// 阶段色点 → 主题令牌（spec C：进行中 = accent，待输入 = success，需处理 = attention）。
    private func dotColor(_ token: QueueDotColor.Token) -> Color {
        switch token {
        case .accent: return .brandAccent
        case .success: return .brandSuccess
        case .attention: return .brandAttention
        }
    }
}

/// 待处理列表的阶段 → 色点令牌映射（epic #1 子任务 C）。
///
/// 与浮条状态色同一套语义：进行中跟主题 accent，结果态用固定语义色。
/// 独立成纯函数枚举，保证规则可脱离界面测试（QueueDotColorTests）。
enum QueueDotColor {
    enum Token {
        case accent
        case success
        case attention
    }

    static func phase(_ phase: InputQueue.Phase) -> Token {
        switch phase {
        case .listening, .transcribing: return .accent
        case .ready: return .success
        case .needsAttention: return .attention
        }
    }
}
