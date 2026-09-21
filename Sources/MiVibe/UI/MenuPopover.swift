import MiVibeCore
import SwiftUI

/// 菜单栏弹窗：状态 + 配对引导 + 待处理内容 + 设置入口（SPEC §7）。
struct MenuPopover: View {
    @ObservedObject var coordinator: Coordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if coordinator.link == .unpaired {
                pairingGuide
            }

            if !permissionsOK {
                permissionNotice
            }

            if !coordinator.queue.items.isEmpty {
                Divider()
                pendingItems
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: - 分段

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: coordinator.link.icon)
                    .foregroundStyle(coordinator.link.color)
                Text(coordinator.link.rawValue)
                    .font(.headline)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("识别引擎")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
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
                    Text(coordinator.asrEngine.displayName)
                }
                .controlSize(.small)
                .help("点击切换识别引擎")
            }
            HStack(spacing: 8) {
                Text("改写模式")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(coordinator.currentModeName) { coordinator.cycleMode() }
                    .controlSize(.small)
                    .help("点击切换到下一个模式；遥控器菜单键可呼出选单")
            }
        }
    }

    private var pairingGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("首次配对").font(.subheadline).bold()
            Text("1. 遥控器进入配对状态（详见说明书）\n2. 点击下方「打开蓝牙设置」\n3. 在列表中选择「小米蓝牙语音遥控器」")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("打开蓝牙设置") { Permissions.openBluetoothSettings() }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var permissionsOK: Bool {
        Permissions.hasAccessibility() && Permissions.hasEventPosting()
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("需要辅助功能权限").font(.subheadline).bold()
            Text("文字要写进别的应用，必须获得「辅助功能」授权。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("打开权限设置") { Permissions.openAccessibilitySettings() }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var pendingItems: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("待处理（\(coordinator.queue.items.count)/2）")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(coordinator.queue.items) { item in
                HStack(spacing: 8) {
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
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("设置…") { openWindow(id: "settings") }
            Spacer()
            Button("退出") { NSApp.terminate(nil) }
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
}
