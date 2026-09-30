import Foundation

/// 待处理列表的阶段 → 色点令牌映射（epic #1 子任务 C）。
///
/// 与浮条状态色同一套语义：进行中跟主题 accent，结果态用固定语义色。
/// 放在 Core 里是为了让 MiVibeTests 直接测真实规则；令牌到颜色的换算在界面层
/// （MenuPopover）完成，这里不依赖 SwiftUI。
public enum QueueDotColor {
    public enum Token: Equatable, Sendable {
        case accent
        case success
        case attention
    }

    public static func phase(_ phase: InputQueue.Phase) -> Token {
        switch phase {
        case .listening, .transcribing: return .accent
        case .ready: return .success
        case .needsAttention: return .attention
        }
    }
}
