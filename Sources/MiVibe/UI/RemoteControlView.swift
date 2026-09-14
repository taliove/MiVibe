import MiVibeCore
import SwiftUI

/// 小米蓝牙语音遥控器 — 使用真实底图，在上面覆盖可点击热区。
///
/// 受控组件：选中态由父视图持有（编辑 UI 在设置页右栏，这里只管"点哪个键"）。
/// 已配置的按键打高亮；语音/电源键不可映射（SPEC §1/§3），不在热区列表里。
struct RemoteControlView: View {
    @Binding var selected: RemoteButton?
    var configured: Set<RemoteButton> = []

    /// 按键热区，坐标实测自底图（887×1774）：x/y 是中心点相对图宽/图高的比例，
    /// d 是直径相对图宽的比例。换底图必须重新量，不能平移旧数值。
    private let hotspots: [(key: RemoteButton, x: CGFloat, y: CGFloat, d: CGFloat)] = [
        (.up,         0.502, 0.180, 0.096),  // 方向环上
        (.down,       0.502, 0.338, 0.096),  // 方向环下
        (.left,       0.344, 0.259, 0.096),  // 方向环左
        (.right,      0.660, 0.259, 0.096),  // 方向环右
        (.confirm,    0.502, 0.259, 0.192),  // 中央确认
        (.back,       0.402, 0.407, 0.147),  // <
        (.home,       0.402, 0.498, 0.147),  // ⌂
        (.menu,       0.402, 0.588, 0.147),  // ≡
        (.volumeUp,   0.605, 0.407, 0.147),  // +
        (.volumeDown, 0.605, 0.498, 0.147),  // −
        (.tv,         0.605, 0.588, 0.147),  // TV
    ]

    var body: some View {
        let image = loadImage()
        // 底图实际长宽比（887×1774 ≈ 0.5）。外层用这个比例约束，GeometryReader
        // 拿到的尺寸就等于图片渲染尺寸，热区比例才能对上。
        let aspect = image.size.width / max(image.size.height, 1)

        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: geo.size.width, height: geo.size.height)

                ForEach(hotspots, id: \.key) { spot in
                    let isConfigured = configured.contains(spot.key)
                    let isSelected = selected == spot.key

                    Button {
                        selected = (selected == spot.key) ? nil : spot.key
                    } label: {
                        Circle()
                            .fill(isSelected ? Color.accentColor.opacity(0.45)
                                  : isConfigured ? Color.blue.opacity(0.3)
                                  : Color.clear)
                            .overlay {
                                Circle()
                                    .stroke(
                                        isSelected || isConfigured
                                            ? Color.white.opacity(0.7) : Color.clear,
                                        lineWidth: 2
                                    )
                            }
                            .frame(
                                width: geo.size.width * spot.d,
                                height: geo.size.width * spot.d
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(spot.key.displayName)
                    .position(
                        x: geo.size.width * spot.x,
                        y: geo.size.height * spot.y
                    )
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
    }

    // MARK: - 加载底图

    private func loadImage() -> NSImage {
        // 先尝试从 bundle 加载
        if let image = NSImage(named: "Mi") {
            return image
        }
        // 开发期降级：从源码目录加载
        let devPath = "<repo>/Sources/MiVibe/Resources/Mi.png"
        if let image = NSImage(contentsOfFile: devPath) {
            return image
        }
        // 找不到时返回占位图
        return NSImage(size: NSSize(width: 887, height: 1774))
    }
}
