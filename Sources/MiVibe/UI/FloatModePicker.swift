import MiVibeCore
import SwiftUI

/// 改写模式选单：↑↓ 移动、确认选定、返回关闭。遥控器专属界面，浮条不抢焦点，
/// 所以这里没有任何可点元素——导航全部由按键路由完成。
///
/// 动效（epic #1 子任务 F）：打开时条目按 20 ms 交错淡入上移（首条延迟 60 ms）；
/// 高亮块是一块 `matchedGeometryEffect` 的填充，在行之间滑动而不是瞬跳；
/// 确认时高亮行闪亮一次（160 ms）。减弱动态效果时全部瞬切。
struct ModePickerView: View {
    let picker: Coordinator.ModePickerState
    let width: CGFloat
    /// 打开代数：每次打开 +1，用来重置交错入场（`onAppear` 不换 id 不会重播）。
    let generation: Int
    /// 确认时闪亮的条目 id（消费一次，下一次打开时自动失效）。
    let confirmingItemID: String?
    let reduceMotion: Bool

    /// 高亮块的 matchedGeometry 命名空间。
    @Namespace private var highlightSpace
    /// 条目入场进度：0 = 未入场（透明 + 下移），1 = 到位。
    @State private var appeared = false
    /// 确认闪亮进度（0…1，160 ms）。
    @State private var flash: Double = 0

    /// 选单内容高度：条目 34 + 页脚 28 + 上下内边距 8。
    static func height(itemCount: Int) -> CGFloat {
        CGFloat(itemCount) * 34 + 28 + 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(picker.items.enumerated()), id: \.element.id) { index, item in
                let isHighlight = index == picker.highlight
                HStack(spacing: 8) {
                    Image(systemName: isHighlight ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isHighlight ? Color.brandOnAccentFill : Color.secondary)
                        .font(.system(size: 13))
                    Text(item.name)
                        .font(.system(size: 14, weight: isHighlight ? .semibold : .regular))
                        .foregroundStyle(isHighlight ? Color.brandOnAccentFill : Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background {
                    if isHighlight {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.brandAccentFill)
                            // 一块高亮块在行之间滑动（减弱动态效果时由系统转为瞬切）。
                            .matchedGeometryEffect(id: "highlight", in: highlightSpace)
                            .brightness(flash * 0.35)
                    }
                }
                .padding(.horizontal, 6)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 4)
                .animation(reduceMotion ? nil : Motion.quick.delay(0.06 + Double(index) * 0.02),
                           value: appeared)
            }
            Text("↑↓ 选择 · 确认键切换 · 返回键关闭")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .frame(height: 28)
                .opacity(appeared ? 1 : 0)
        }
        .padding(.vertical, 8)
        .frame(width: width)
        .animation(reduceMotion ? nil : Motion.standard, value: picker.highlight)
        .id(generation)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                appeared = false
                withAnimation { appeared = true }
            }
        }
        .onChange(of: confirmingItemID) { _, id in
            guard id != nil, !reduceMotion else { return }
            flash = 0
            withAnimation(Motion.instant) { flash = 1 }
            withAnimation(Motion.instant.delay(MotionTiming.pickerConfirmFlash)) { flash = 0 }
        }
    }
}
