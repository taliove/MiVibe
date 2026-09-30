// 生成 MiVibe 应用图标（epic #1 子任务 B）：苹果官方圆角矩形满铺，
// 潮汐青渐变 + 白色品牌标记（三根声波 + 文本光标）。
//
// 形状取自系统合规图标（Calculator）的完整未阈值化 alpha——macOS 26 上
// 任何带透明边距的图标都会被套上灰色底板（icon jail），只有图标本体就是
// 苹果圆角矩形形状才能逃脱。内容边缘缩到 865 / 1024（84.5%），经 IconServices
// 渲染后与系统应用同为 87.6% 足迹（macos-app-icon.md 实测校准）。
//
// 用法：swift Scripts/make-icon.swift（需要 GUI 会话，NSWorkspace 取系统图标）
// 输出：Sources/MiVibe/Resources/AppIcon.icns（入库；CI 不运行本脚本）
import AppKit
import CoreGraphics

// Copy of BrandMark.bars — keep identical
// 100 单位网格 (x, y, w, h)，y 向上：三根声波 → 光标柱 → 两条衬线。
let bars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (17, 40, 9, 20),
    (31, 28, 9, 44),
    (45, 36, 9, 28),
    (66, 21, 8, 58),
    (59, 18, 22, 7),
    (59, 75, 22, 7),
]
// Copy of BrandMark.cornerRadii — keep identical
let cornerRadii: [CGFloat] = [4.5, 4.5, 4.5, 4, 3.5, 3.5]

// 潮汐青 iconTop / iconBottom（ThemePalette.palette(.tide)，脚本不能导入应用模块）。
let iconTop = (r: CGFloat(0x16) / 255, g: CGFloat(0xB4) / 255, b: CGFloat(0xC2) / 255)
let iconBottom = (r: CGFloat(0x08) / 255, g: CGFloat(0x69) / 255, b: CGFloat(0x78) / 255)

let canvas = 1024          // 主画布
let squircleEdge = 865     // 圆角矩形内容边缘（84.5%），见文件头注释
let markFraction = 0.64    // 标记占圆角矩形的比例

// MARK: - 系统圆角矩形 alpha 模板

/// 渲染 Calculator 图标到显式 1024px 位图，取完整 alpha（不做阈值，保留柔和阴影衰减）。
/// 注意：NSImage.lockFocus 出来的位图是 2048px（点 ≠ 像素），必须画进自建位图。
func squircleTemplate() -> CGImage {
    let icon = NSWorkspace.shared.icon(forFile: "/System/Applications/Calculator.app")
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("无法创建位图") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    icon.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas),
              from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let cg = rep.cgImage else { fatalError("无法渲染系统图标") }

    // alpha bbox：非全透明的范围（含柔和阴影，约 87% of canvas）
    guard let data = cg.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data)
    else { fatalError("无法读取系统图标像素") }
    let w = cg.width, h = cg.height, bpr = cg.bytesPerRow
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            if bytes[y * bpr + x * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX > minX, maxY > minY else { fatalError("系统图标 alpha 为空") }
    let bbox = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    print(String(format: "系统图标 alpha bbox：%dx%d（%.1f%% of canvas）",
                 Int(bbox.width), Int(bbox.height),
                 Double(bbox.width) / Double(canvas) * 100))
    guard let mask = cg.cropping(to: bbox) else { fatalError("无法裁剪模板") }
    return mask
}

// MARK: - 标记路径

/// 100 网格 → 目标矩形，y 翻转（CG 上下文 y 向上，网格语义 y 向上，保持一致）。
func markPath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let scale = min(rect.width, rect.height) / 100
    let offsetX = rect.minX + (rect.width - 100 * scale) / 2
    let offsetY = rect.minY + (rect.height - 100 * scale) / 2
    for (index, bar) in bars.enumerated() {
        var transform = CGAffineTransform(translationX: offsetX, y: offsetY)
            .scaledBy(x: scale, y: scale)
        let rect100 = CGRect(x: bar.0, y: bar.1, width: bar.2, height: bar.3)
        let r = cornerRadii[index]
        path.addPath(CGPath(roundedRect: rect100, cornerWidth: r, cornerHeight: r,
                            transform: &transform))
    }
    return path
}

// MARK: - 渲染

func render(px: Int, template: CGImage) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("无法创建位图") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("无图形上下文") }
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(px)

    // 目标圆角矩形：865 / 1024 等比缩放到当前分辨率，居中。
    let edge = s * CGFloat(squircleEdge) / CGFloat(canvas)
    let target = CGRect(x: (s - edge) / 2, y: (s - edge) / 2, width: edge, height: edge)

    // 1. 模板裁出圆角矩形形状（模板是正方形 bbox，直接铺满 target）。
    ctx.saveGState()
    ctx.clip(to: target, mask: template)

    // 2. 垂直渐变（iconTop 在上 → iconBottom 在下）。
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: iconTop.r, green: iconTop.g, blue: iconTop.b, alpha: 1),
        CGColor(red: iconBottom.r, green: iconBottom.g, blue: iconBottom.b, alpha: 1),
    ] as CFArray
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])
    else { fatalError("无法创建渐变") }
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: target.midX, y: target.maxY),
                           end: CGPoint(x: target.midX, y: target.minY),
                           options: [])
    ctx.restoreGState()

    // 3. 白色标记，占圆角矩形中央 64%。
    let markEdge = edge * markFraction
    let markRect = CGRect(x: target.midX - markEdge / 2, y: target.midY - markEdge / 2,
                          width: markEdge, height: markEdge)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(markPath(in: markRect))
    ctx.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - 主流程

let template = squircleTemplate()

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, px) in sizes {
    let rep = render(px: px, template: template)
    guard let png = rep.representation(using: .png, properties: [:])
    else { fatalError("渲染失败：\(px)") }
    try png.write(to: iconset.appendingPathComponent(name))
}

let output = root.appendingPathComponent("Sources/MiVibe/Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil 失败：\(task.terminationStatus)") }
print("已写出 \(output.path)")
