import MiVibeCore
import SwiftUI

/// 「选中按键」编辑卡：头部键徽标 + 名称 + HID usage，主体按绑定来源切换文案。
///
/// 四种来源（`KeyBindingSource`）对应四种编辑姿态：
/// - 默认作用范围（`own` / `unbound`）：直接录制 / 清除 / 设为动作；
/// - 应用作用范围 `inherited`：显示继承自哪条默认绑定，可「在此应用覆盖」；
/// - 应用作用范围 `overridden`：显示默认对照，可「恢复继承」；
/// - 应用作用范围 `unbound`：录制或设动作即成为覆盖。
struct KeyMappingSelectedCard: View {
    @ObservedObject var coordinator: Coordinator
    let scope: String?
    @Binding var selectedButton: RemoteButton?

    /// 非 nil 时驱动 ShortcutRecorder 进入录制态（「在此应用覆盖」一键录制用）。
    @State private var recordToken: UUID?

    /// 当前作用范围实际生效的映射表（显示绑定文本用；来源判断走 bindingSource）。
    private var effectiveMapping: AppMapping {
        coordinator.keyMap.mapping(forBundleID: scope)
    }

    var body: some View {
        SettingsGroup(
            title: "选中按键",
            footer: "录音/转写进行中，返回键优先用于取消，不触发映射。未映射的键保持系统原生行为。应用内动作触发 MiVibe 自身功能（如改写模式选单），不发送键盘事件。"
        ) {
            if let button = selectedButton {
                header(button)
                Divider()
                body(for: button)
            } else {
                Text("点击左侧遥控器上的按键进行配置。")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.rowH)
                    .padding(.vertical, Spacing.rowV + 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 头部

    /// 键徽标 + 名称 + HID usage，明确「正在编辑哪个键」。
    private func header(_ button: RemoteButton) -> some View {
        HStack(spacing: Spacing.intra) {
            Text(Self.badge(for: button))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(button.displayName)键").font(.headline)
                Text(String(format: "HID usage 0x%02X", button.rawValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.rowH)
        .padding(.vertical, Spacing.rowV)
        .animation(Motion.select, value: selectedButton)
    }

    /// 键徽标上的短字符（方向用箭头，确认用 OK，与实物键帽观感一致）。
    static func badge(for button: RemoteButton) -> String {
        switch button {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .confirm: return "OK"
        case .back: return "<"
        case .volumeUp: return "+"
        case .volumeDown: return "−"
        case .home: return "⌂"
        case .menu: return "≡"
        case .tv: return "TV"
        case .voice: return "🎤"
        case .power: return "⏻"
        }
    }

    /// 已配置列表的行图标。
    static func icon(for button: RemoteButton) -> String {
        switch button {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .confirm: return "checkmark"
        case .back: return "arrow.uturn.left"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .home: return "house"
        case .menu: return "line.3.horizontal"
        case .tv: return "tv"
        case .voice: return "mic"
        case .power: return "power"
        }
    }

    // MARK: - 主体（按来源分派）

    @ViewBuilder
    private func body(for button: RemoteButton) -> some View {
        let source = coordinator.keyMap.bindingSource(of: button, forBundleID: scope)
        if scope == nil {
            // 默认作用范围只可能出现 own / unbound，编辑姿态相同。
            defaultEditingRows(button, source: source)
        } else {
            switch source {
            case .inherited:
                inheritedRows(button)
            case .overridden:
                overriddenRows(button)
            case .unbound, .own:
                // own 在应用作用范围不会出现，兜底按未绑定处理（写入即成为覆盖）。
                unboundAppRows(button)
            }
        }
    }

    // MARK: 默认作用范围

    /// 默认映射的编辑行：动作绑定优先展示；否则快捷键录制 + 清除 + 设为动作。
    @ViewBuilder
    private func defaultEditingRows(_ button: RemoteButton, source: KeyBindingSource) -> some View {
        if let action = effectiveMapping[action: button] {
            // 已绑定应用内动作：与快捷键互斥（见 AppMapping）。
            SettingsRow(icon: "bolt.fill", title: "应用内动作",
                        subtitle: action.displayName) {
                Button("清除") {
                    coordinator.setAction(nil, for: button, in: scope)
                }
                .controlSize(.small)
            }
        } else {
            SettingsRow(icon: "keyboard", title: "快捷键",
                        subtitle: effectiveMapping[button]?.display ?? "未设置") {
                HStack(spacing: 8) {
                    ShortcutRecorder(shortcut: effectiveMapping[button],
                                     autoRecordToken: $recordToken) { shortcut in
                        coordinator.setShortcut(shortcut, for: button, in: scope)
                    }
                    if effectiveMapping[button] != nil {
                        Button("清除") {
                            coordinator.setShortcut(nil, for: button, in: scope)
                        }
                        .controlSize(.small)
                    }
                    actionMenu(button)
                }
            }
        }
    }

    // MARK: 应用作用范围 · 继承

    /// 继承态：先一行说明继承自哪条默认绑定，再给「在此应用覆盖」（一键录制）
    /// 与「设为动作…」。任一写入都会成为该应用的覆盖。
    @ViewBuilder
    private func inheritedRows(_ button: RemoteButton) -> some View {
        let defaultMapping = coordinator.keyMap.defaultMapping
        let inheritedText = defaultMapping[action: button].map { "动作：\($0.displayName)" }
            ?? defaultMapping[button]?.display ?? ""
        SettingsRow(icon: "arrow.triangle.branch", iconColor: .gray,
                    title: "继承自默认：\(inheritedText)",
                    subtitle: "该应用没有自己的绑定，跟随默认映射") {
            HStack(spacing: 8) {
                Button("在此应用覆盖") { recordToken = UUID() }
                    .controlSize(.small)
                actionMenu(button)
            }
        }
        RowDivider()
        SettingsRow(icon: "keyboard", title: "快捷键",
                    subtitle: "录制后即成为该应用的覆盖") {
            ShortcutRecorder(shortcut: effectiveMapping[button],
                             autoRecordToken: $recordToken) { shortcut in
                coordinator.setShortcut(shortcut, for: button, in: scope)
            }
        }
    }

    // MARK: 应用作用范围 · 已覆盖

    /// 已覆盖：对照显示默认绑定，编辑行与默认作用范围相同，另加「恢复继承」。
    @ViewBuilder
    private func overriddenRows(_ button: RemoteButton) -> some View {
        let defaultMapping = coordinator.keyMap.defaultMapping
        let defaultText = defaultMapping[action: button].map { "动作：\($0.displayName)" }
            ?? defaultMapping[button]?.display
        SettingsRow(icon: "pencil.circle", title: "已覆盖",
                    subtitle: defaultText.map { "默认为 \($0)" } ?? "默认未绑定") {
            Button("恢复继承") {
                // 清除该作用范围的快捷键与动作：覆盖表不再持有该键即回到继承
                // （见 KeyMapTable.updateMapping——清除覆盖 = 回到继承）。
                coordinator.setShortcut(nil, for: button, in: scope)
                coordinator.setAction(nil, for: button, in: scope)
            }
            .controlSize(.small)
        }
        RowDivider()
        defaultEditingRows(button, source: .overridden)
    }

    // MARK: 应用作用范围 · 未绑定

    /// 应用作用范围里两边都没有绑定：录制或设动作即成为覆盖。
    private func unboundAppRows(_ button: RemoteButton) -> some View {
        SettingsRow(icon: "keyboard", title: "快捷键",
                    subtitle: "未绑定 · 录制后即成为该应用的覆盖") {
            HStack(spacing: 8) {
                ShortcutRecorder(shortcut: nil, autoRecordToken: $recordToken) { shortcut in
                    coordinator.setShortcut(shortcut, for: button, in: scope)
                }
                actionMenu(button)
            }
        }
    }

    // MARK: - 公共控件

    /// 「设为动作…」菜单，与快捷键互斥（写入动作会顶掉同键快捷键）。
    private func actionMenu(_ button: RemoteButton) -> some View {
        Menu("设为动作…") {
            ForEach(RemoteAction.allCases, id: \.self) { action in
                Button(action.displayName) {
                    coordinator.setAction(action, for: button, in: scope)
                }
            }
        }
        .controlSize(.small)
        .fixedSize()
    }
}
