import SwiftUI
import AppKit

// ============================================================
// MiVibe 界面原型（13 票）——抛弃式，不连蓝牙/ASR/注入
// 回答的问题：原生 SwiftUI 下菜单栏三态、底部浮条四状态、设置页、
// 配对引导的观感；顺带实测 .nonactivatingPanel 是否真不抢焦点。
// 运行：swiftc -O -o /tmp/MiVibeProto MiVibeProto.swift && /tmp/MiVibeProto
// ============================================================

// MARK: - 模型（全部内存态，无任何持久化）

enum LinkState: String, CaseIterable, Identifiable {
    case unpaired = "未配对"
    case pairedOffline = "已配对·未连接"
    case connected = "已连接"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .unpaired: return "mic.badge.plus"
        case .pairedOffline: return "mic.slash"
        case .connected: return "mic.fill"
        }
    }
    var color: Color {
        switch self {
        case .unpaired: return .orange
        case .pairedOffline: return .secondary
        case .connected: return .green
        }
    }
}

enum FloatState: String, CaseIterable, Identifiable {
    case listening, transcribing, inserted, attention
    var id: String { rawValue }
    var label: String {
        switch self {
        case .listening: return "正在听"
        case .transcribing: return "正在转写"
        case .inserted: return "已输入"
        case .attention: return "需处理"
        }
    }
    var message: String {
        switch self {
        case .listening: return "松开语音键结束"
        case .transcribing: return "可以说下一句"
        case .inserted: return "文字已写入目标输入框"
        case .attention: return "请选好输入框后点击「输入到这里」"
        }
    }
    var color: Color {
        switch self {
        case .listening: return Color(red: 0.09, green: 0.47, blue: 0.94)
        case .transcribing: return Color(red: 0.44, green: 0.31, blue: 0.86)
        case .inserted: return Color(red: 0.03, green: 0.55, blue: 0.38)
        case .attention: return Color(red: 0.78, green: 0.42, blue: 0.0)
        }
    }
}

final class ProtoModel: ObservableObject {
    @Published var link: LinkState = .connected
    @Published var float: FloatState? = .listening
    @Published var apiKeyDraft = ""
    @Published var nonstream = true
    @Published var demoMode = false

    private var demoTimer: Timer?
    private var demoIndex = 0
    func toggleDemo() {
        demoMode.toggle()
        demoTimer?.invalidate()
        guard demoMode else { return }
        let order: [FloatState?] = [.listening, .transcribing, .inserted, .attention, nil]
        demoIndex = 0
        demoTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.float = order[self.demoIndex % order.count]
                self.demoIndex += 1
                if !self.demoMode { self.demoTimer?.invalidate() }
            }
        }
    }
}

// MARK: - 底部浮条（.nonactivatingPanel 实测对象）

final class FloatPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 56),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // 阴影由 SwiftUI 层绘制
        hidesOnDeactivate = false
        isMovable = false
    }
    // 双重保险：即使被点也不成为 key/main
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.minY + 22))
    }
}

struct FloatBarView: View {
    let state: FloatState
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(state.color).frame(width: 9, height: 9)
            Text(state.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            Text(state.message).font(.system(size: 13)).foregroundStyle(Color(white: 0.84))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(width: 560, height: 56)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

// MARK: - 菜单栏弹窗内容

struct MenuPopover: View {
    @ObservedObject var model: ProtoModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: model.link.icon).foregroundStyle(model.link.color)
                Text(model.link.rawValue).font(.headline)
                Spacer()
                Text("原型").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if model.link == .unpaired {
                VStack(alignment: .leading, spacing: 6) {
                    Text("首次配对").font(.subheadline).bold()
                    Text("1. 遥控器进入配对状态（详见说明书）\n2. 点击下方「打开蓝牙设置」\n3. 在列表中选择「小米蓝牙语音遥控器」")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("打开蓝牙设置") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Bluetooth")!)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("模拟（演示用）").font(.caption).foregroundStyle(.secondary)
                Picker("连接状态", selection: $model.link) {
                    ForEach(LinkState.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                HStack(spacing: 6) {
                    ForEach(FloatState.allCases) { s in
                        Button(s.label) { model.float = s }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    Button("隐藏") { model.float = nil }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                Toggle("演示模式：自动轮播四状态（用来验证不抢焦点）", isOn: Binding(
                    get: { model.demoMode }, set: { _ in model.toggleDemo() }))
                    .font(.callout)
            }

            Divider()

            HStack {
                Button("设置…") { openWindow(id: "settings") }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

// MARK: - 设置页（标准 macOS 惯例：工具栏分页 + 分组表单 + 短标签 + 脚注说明）

struct SettingsView: View {
    @ObservedObject var model: ProtoModel
    var body: some View {
        TabView {
            Form {
                Section {
                    LabeledContent("API Key:") {
                        SecureField("粘贴 API Key", text: $model.apiKeyDraft)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("状态:") {
                        Text(model.apiKeyDraft.isEmpty ? "未配置" : "已录入（\(model.apiKeyDraft.count) 字符）")
                            .foregroundStyle(model.apiKeyDraft.isEmpty ? Color.secondary : Color.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    LabeledContent("二遍识别:") {
                        Toggle("", isOn: $model.nonstream).labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } footer: {
                    Text("Key 只存入本机钥匙串。二遍识别换来更准的标点分句，尾延迟约 +0.6s（实测 0.77s）。")
                }
                Section {
                    LabeledContent("申请 Key:") {
                        Button("打开语音控制台…") {
                            NSWorkspace.shared.open(URL(string: "https://console.volcengine.com/speech/new/setting/apikeys?projectName=default")!)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("豆包语音", systemImage: "waveform") }

            Form {
                Section {
                    LabeledContent("连接状态:") {
                        HStack(spacing: 6) {
                            Circle().fill(model.link.color).frame(width: 8, height: 8)
                            Text(model.link.rawValue)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    LabeledContent("系统蓝牙:") {
                        Button("打开蓝牙设置…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Bluetooth")!)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } footer: {
                    Text("未配对时按遥控器说明书进入配对状态，再到系统蓝牙设置中选择「小米蓝牙语音遥控器」。")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("遥控器", systemImage: "av.remote") }

            Form {
                Section {
                    LabeledContent("版本:") { Text("界面原型（抛弃式）").frame(maxWidth: .infinity, alignment: .leading) }
                    LabeledContent("数据:") { Text("不连接真实设备，无持久化").frame(maxWidth: .infinity, alignment: .leading) }
                } footer: {
                    Text("此原型只回答界面观感问题；状态均为模拟。")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 440, height: 400)
    }
}

// MARK: - App 骨架

let protoModel = ProtoModel()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatPanel?
    private var shown: FloatState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let panel = FloatPanel()
        panel.positionBottomCenter()
        self.panel = panel
        updatePanel()
        // 原型用 200ms 轮询驱动面板，不上 Combine 管道
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updatePanel() }
        }
    }

    @MainActor private func updatePanel() {
        guard let panel else { return }
        let target = protoModel.float
        guard target != shown else { return }
        shown = target
        if let target {
            panel.contentView = NSHostingView(rootView: FloatBarView(state: target))
            panel.positionBottomCenter()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }
}

struct MenuIconView: View {
    @ObservedObject var model = protoModel
    var body: some View { Image(systemName: model.link.icon) }
}

@main
struct MiVibeProtoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuPopover(model: protoModel)
        } label: {
            MenuIconView()
        }
        .menuBarExtraStyle(.window)

        Window("设置", id: "settings") {
            SettingsView(model: protoModel)
        }
        .windowResizability(.contentSize)
    }
}
