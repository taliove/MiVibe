import MiVibeCore
import SwiftUI

/// 小米蓝牙语音遥控器 — 用矢量图形程序绘制，按键本身就是可点击热区。
///
/// 为什么不用照片底图：照片四周留白大，缩进设置页后遥控器本体只剩一半宽；
/// 热区还得按像素比例另量一套。这里机身、按键、热区共用一套单位坐标
/// （机身宽 = 100），视图多大遥控器就多大，放大也不糊。比例参照实物量取，
/// 只把按键区以下的空白机身按比例缩短了。
///
/// 受控组件：选中态由父视图持有（编辑 UI 在设置页右栏，这里只管"点哪个键"）。
/// 按键按绑定来源描边：自有 / 已覆盖描强调色边，继承描灰色细边，未绑定不描；
/// 语音/电源键不可映射（SPEC §1/§3），只画不响应。
/// 热区支持右键菜单（选中编辑 / 设为动作 / 清除映射 / 恢复继承），与右栏编辑区等效。
struct RemoteControlView: View {
    @Binding var selected: RemoteButton?
    /// 每个可映射键在当前作用范围里的绑定来源（决定描边与右键菜单文案）。
    var sources: [RemoteButton: KeyBindingSource] = [:]
    /// 实体键「按下即亮」回显（来自 Coordinator.pressedButton）。热区只覆盖可映射键，
    /// 语音/电源键的按下不在图上回显。
    var flashing: RemoteButton? = nil
    /// 右键菜单动作：为 nil 时不提供对应菜单项。
    /// onClear 在默认作用范围是「清除映射」，在应用作用范围的已覆盖键上是「恢复继承」，
    /// 语义由调用方决定（本视图只按 source 换文案）。
    var onClear: ((RemoteButton) -> Void)? = nil
    var onSetAction: ((RemoteButton, RemoteAction) -> Void)? = nil

    /// 设置页中的推荐宽度（高度由机身比例决定）。
    static let preferredWidth: CGFloat = 130

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / Layout.width
            ZStack(alignment: .topLeading) {
                chassis
                fixedParts(unit)
                ForEach(Layout.keys, id: \.button) { key in
                    keyButton(key, unit: unit)
                }
            }
        }
        .aspectRatio(Layout.width / Layout.height, contentMode: .fit)
    }

    // MARK: - 机身与不可映射部件

    private var chassis: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape
            .fill(LinearGradient(colors: Palette.aluminium, startPoint: .leading, endPoint: .trailing))
            .overlay(shape.strokeBorder(Color.black.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            .accessibilityHidden(true)
    }

    /// 电源 / 语音（不可映射）、方向环底座、音量条、NFC 标记。
    private func fixedParts(_ unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Layout.silverKeys, id: \.symbol) { key in
                Circle()
                    .fill(LinearGradient(colors: Palette.aluminium.reversed(),
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(Palette.silverRim, lineWidth: 1.2))
                    .overlay(glyph(key.symbol, diameter: key.d, unit: unit, color: Palette.silverGlyph))
                    .place(x: key.x, y: key.y, d: key.d, unit: unit)
            }

            Circle()
                .fill(LinearGradient(colors: Palette.darkKey, startPoint: .top, endPoint: .bottom))
                .place(x: Layout.pad.x, y: Layout.pad.y, d: Layout.pad.ring, unit: unit)

            Capsule()
                .fill(LinearGradient(colors: Palette.darkKey, startPoint: .top, endPoint: .bottom))
                .frame(width: Layout.volume.w * unit, height: Layout.volume.h * unit)
                .position(x: Layout.volume.x * unit, y: Layout.volume.y * unit)

            RoundedRectangle(cornerRadius: 1.5 * unit)
                .fill(Palette.nfc)
                .overlay(Text("N")
                    .font(.system(size: 6 * unit, weight: .heavy))
                    .foregroundStyle(Palette.aluminium[2]))
                .place(x: Layout.nfc.x, y: Layout.nfc.y, d: 8, unit: unit)
        }
        .accessibilityHidden(true)
    }

    // MARK: - 可映射按键

    private func keyButton(_ key: Layout.Key, unit: CGFloat) -> some View {
        let source = sources[key.button] ?? .unbound
        let isSelected = selected == key.button
        let isFlashing = flashing == key.button

        return Button {
            selected = isSelected ? nil : key.button
        } label: {
            ZStack {
                keyFace(key)
                Circle()
                    .fill(isFlashing ? Color.brandAccent.opacity(0.9)
                          : isSelected ? Color.brandAccent.opacity(0.8)
                          : Color.clear)
                Circle()
                    .strokeBorder(isSelected || isFlashing ? Color.white.opacity(0.9)
                                  : strokeColor(for: source),
                                  lineWidth: strokeWidth(for: source, unit: unit))
                if let symbol = key.symbol {
                    glyph(symbol, diameter: key.d, unit: unit, color: .white)
                } else {
                    // 方向键只有一个小圆点，与实物一致。
                    Circle()
                        .fill(Color.white.opacity(isSelected || isFlashing ? 1 : 0.6))
                        .frame(width: 2 * unit, height: 2 * unit)
                }
            }
            .contentShape(Circle())
            .animation(Motion.select, value: isFlashing)
            .animation(Motion.select, value: isSelected)
        }
        .buttonStyle(.plain)
        .place(x: key.x, y: key.y, d: key.d, unit: unit)
        .help(key.button.displayName)
        .accessibilityLabel("\(key.button.displayName)键")
        .accessibilityHint(source == .unbound ? "未配置，双击编辑" : "已配置映射，双击编辑")
        .contextMenu {
            Button(isSelected ? "取消选中" : "选中编辑") {
                selected = isSelected ? nil : key.button
            }
            if let onSetAction {
                Menu("设为动作") {
                    ForEach(RemoteAction.allCases, id: \.self) { action in
                        Button(action.displayName) { onSetAction(key.button, action) }
                    }
                }
            }
            if let onClear, source == .own || source == .overridden {
                Divider()
                Button(source == .overridden ? "恢复继承" : "清除映射",
                       role: .destructive) { onClear(key.button) }
            }
        }
    }

    /// 绑定来源对应的描边颜色：自有 / 覆盖用主题色，继承用灰色，未绑定不描。
    private func strokeColor(for source: KeyBindingSource) -> Color {
        switch source {
        case .own, .overridden: return Color.brandAccent
        case .inherited: return Color.gray.opacity(0.7)
        case .unbound: return Color.clear
        }
    }

    /// 继承的描边更细一档，与「它不是这个作用范围自己的绑定」的视觉权重一致。
    private func strokeWidth(for source: KeyBindingSource, unit: CGFloat) -> CGFloat {
        switch source {
        case .own, .overridden: return max(1.5, 1.2 * unit)
        case .inherited: return max(1, 0.8 * unit)
        case .unbound: return max(1.5, 1.2 * unit)   // 描边透明，线宽无视觉影响
        }
    }

    /// 按键底面：独立圆键画深色键帽；方向键与音量键的底座已在 fixedParts 画好。
    @ViewBuilder
    private func keyFace(_ key: Layout.Key) -> some View {
        switch key.face {
        case .cap:
            Circle()
                .fill(LinearGradient(colors: Palette.darkKey, startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        case .center:
            Circle()
                .fill(Palette.centerKey)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1))
        case .onBase:
            Color.clear
        }
    }

    private func glyph(_ symbol: String, diameter: CGFloat, unit: CGFloat, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: diameter * unit * 0.36, weight: .medium))
            .foregroundStyle(color)
    }
}

// MARK: - 几何与配色

private extension RemoteControlView {
    /// 单位坐标：机身宽 100。x/y 为中心点，d 为直径。数值量自实物照片
    /// （机身 430px 宽 ≈ 4.3px/单位），按键区以下机身按比例缩短。
    enum Layout {
        static let width: CGFloat = 100
        static let height: CGFloat = 290

        enum Face { case cap, center, onBase }

        struct Key {
            let button: RemoteButton
            let x: CGFloat, y: CGFloat, d: CGFloat
            /// nil = 方向键小圆点。
            let symbol: String?
            let face: Face
        }

        struct SilverKey {
            let symbol: String
            let x: CGFloat, y: CGFloat, d: CGFloat
        }

        /// 方向环：外径 ring、中央确认键直径 center；方向热区落在环宽中线上。
        static let pad = (x: CGFloat(50), y: CGFloat(93), ring: CGFloat(82), center: CGFloat(43))
        private static let padArm = (pad.ring + pad.center) / 4
        private static let arrowD: CGFloat = 20

        private static let left: CGFloat = 29, right: CGFloat = 71
        private static let rows: [CGFloat] = [154, 192, 230]
        private static let keyD: CGFloat = 32

        /// 音量条：覆盖 + / − 两行。
        static let volume = (x: right, y: (rows[0] + rows[1]) / 2,
                             w: keyD, h: rows[1] - rows[0] + keyD)
        static let nfc = (x: CGFloat(50), y: CGFloat(262))

        static let silverKeys: [SilverKey] = [
            SilverKey(symbol: "power", x: 25, y: 30, d: 23),
            SilverKey(symbol: "mic", x: 75, y: 30, d: 23),
        ]

        static let keys: [Key] = [
            Key(button: .up, x: pad.x, y: pad.y - padArm, d: arrowD, symbol: nil, face: .onBase),
            Key(button: .down, x: pad.x, y: pad.y + padArm, d: arrowD, symbol: nil, face: .onBase),
            Key(button: .left, x: pad.x - padArm, y: pad.y, d: arrowD, symbol: nil, face: .onBase),
            Key(button: .right, x: pad.x + padArm, y: pad.y, d: arrowD, symbol: nil, face: .onBase),
            Key(button: .confirm, x: pad.x, y: pad.y, d: pad.center, symbol: nil, face: .center),
            Key(button: .back, x: left, y: rows[0], d: keyD, symbol: "chevron.left", face: .cap),
            Key(button: .home, x: left, y: rows[1], d: keyD, symbol: "house", face: .cap),
            Key(button: .menu, x: left, y: rows[2], d: keyD, symbol: "line.3.horizontal", face: .cap),
            Key(button: .volumeUp, x: right, y: rows[0], d: keyD, symbol: "plus", face: .onBase),
            Key(button: .volumeDown, x: right, y: rows[1], d: keyD, symbol: "minus", face: .onBase),
            Key(button: .tv, x: right, y: rows[2], d: keyD, symbol: "tv", face: .cap),
        ]
    }

    /// 实物配色：铝合金机身（横向明暗模拟圆弧侧面）+ 深灰键帽。
    /// 两种外观下都保持实物颜色，不跟随系统深浅色。
    enum Palette {
        static let aluminium: [Color] = [
            Color(white: 0.70), Color(white: 0.86), Color(white: 0.93),
            Color(white: 0.87), Color(white: 0.68),
        ]
        static let darkKey: [Color] = [Color(white: 0.27), Color(white: 0.13)]
        static let centerKey = Color(white: 0.17)
        static let silverRim = Color(white: 0.42)
        static let silverGlyph = Color(white: 0.25)
        static let nfc = Color(white: 0.45)
    }
}

private extension View {
    /// 以单位坐标的中心点与直径摆放一个正方形元素。
    func place(x: CGFloat, y: CGFloat, d: CGFloat, unit: CGFloat) -> some View {
        frame(width: d * unit, height: d * unit)
            .position(x: x * unit, y: y * unit)
    }
}
