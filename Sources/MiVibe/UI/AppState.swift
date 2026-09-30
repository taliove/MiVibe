import SwiftUI

/// 菜单栏三态（SPEC §7）。
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

    /// 链路状态用固定语义色：已连接=成功，已配对未连接=中性提示，未配对=需要注意。
    @MainActor var color: Color {
        switch self {
        case .unpaired: return .brandAttention
        case .pairedOffline: return .brandNotice
        case .connected: return .brandSuccess
        }
    }
}

/// 浮条状态（SPEC §6，07 票确认；后增 polishing 与 notice）。
enum FloatState: String, CaseIterable, Identifiable {
    case listening, transcribing, polishing, inserted, notice, attention

    var id: String { rawValue }

    var label: String {
        switch self {
        case .listening: return "正在听"
        case .transcribing: return "正在转写"
        case .polishing: return "正在改写"
        case .inserted: return "已输入"
        case .notice: return "提示"
        case .attention: return "需处理"
        }
    }

    /// 默认指引文案；有具体消息时由调用方覆盖。
    var hint: String {
        switch self {
        case .listening: return "松开语音键结束"
        case .transcribing: return "可以说下一句"
        case .polishing: return "正在让语言模型整理文字"
        case .inserted: return "文字已写入目标输入框"
        case .notice: return ""
        case .attention: return "请选好输入框后点击「输入到这里」"
        }
    }

    /// 进行中状态用主题色（随用户主题变化），结果状态用固定语义色（epic 颜色规则）。
    @MainActor var color: Color {
        switch self {
        case .listening, .transcribing, .polishing: return .brandAccent
        case .inserted: return .brandSuccess
        case .notice: return .brandNotice
        case .attention: return .brandAttention
        }
    }
}
