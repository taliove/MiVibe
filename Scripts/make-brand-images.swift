// 生成 MiVibe 品牌分发图（epic #1 子任务 E，规格 .scratch/mivibe/design/spec-draft/E.md）：
// README 主图（浅 / 深两张）与 GitHub 社交预览图，全部来自与应用图标相同的绘制参数。
//
// 输出（入库，随仓库分发）：
//   docs/images/hero-light.png      1240×400（620×200 pt @2x，透明背景）
//   docs/images/hero-dark.png       1240×400（620×200 pt @2x，透明背景）
//   docs/images/social-preview.png  1280×640（墨底，仓库设置手动上传）
//
// 版式坐标取自 .scratch/mivibe/design/design-system-v3.html 场景 4 的 SVG：
//   - 主图几何在 620×200 pt 设计空间（SVG 顶左原点），渲染时 scale 2 到 1240×400 px；
//   - 社交预览图几何直接给在 1280×640 px 空间，scale 1 渲染。
// CG 上下文原点在左下，脚本把设计稿的「顶左原点」坐标显式换算（cgY = 画布高 - 设计 y），
// 不依赖 NSGraphicsContext 的翻转约定。PNG 经 CGImageDestination 不带元数据写出，
// 重复运行字节一致（shasum 可验证）。
//
// 用法：swift Scripts/make-brand-images.swift（在仓库根目录执行，AppKit，无需 GUI 会话）
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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

// 潮汐青（ThemePalette.palette(.tide) 的逐字取值，脚本不能导入应用模块）。
let iconTop = (r: CGFloat(0x16) / 255, g: CGFloat(0xB4) / 255, b: CGFloat(0xC2) / 255)
let iconBottom = (r: CGFloat(0x08) / 255, g: CGFloat(0x69) / 255, b: CGFloat(0x78) / 255)
let accent = (r: CGFloat(0x0C) / 255, g: CGFloat(0x98) / 255, b: CGFloat(0xA8) / 255)
let accentDark = (r: CGFloat(0x22) / 255, g: CGFloat(0xB8) / 255, b: CGFloat(0xC6) / 255)
let ink = (r: CGFloat(0x0E) / 255, g: CGFloat(0x1A) / 255, b: CGFloat(0x1F) / 255)

// 与 make-icon.swift 相同的图标几何常量。
let iconCanvas = 1024
let squircleEdge = 865
let markFraction = 0.64

// 100 网格 → 目标矩形（与 make-icon.swift 的 markPath 相同）。
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

// MARK: - 设计坐标（顶左原点）→ CG 坐标（左下原点）

/// 把一个设计稿矩形（顶左原点）换算到 CG 上下文。canvasH 为 pt 画布高。
func cgRect(x: CGFloat, topY: CGFloat, width: CGFloat, height: CGFloat,
            canvasH: CGFloat) -> CGRect {
    CGRect(x: x, y: canvasH - topY - height, width: width, height: height)
}

/// 设计稿基线 y（顶左原点）→ CG 基线 y。
func cgBaseline(_ designY: CGFloat, canvasH: CGFloat) -> CGFloat { canvasH - designY }

// MARK: - 绘制原语

func fillRounded(_ rect: CGRect, radius: CGFloat, color: NSColor, in ctx: CGContext,
                 alpha: CGFloat = 1) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    color.setFill()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                       transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
}

func drawIcon(centerX: CGFloat, centerY: CGFloat, edge: CGFloat, in ctx: CGContext) {
    // 外框与应用图标同形：865/1024 的内容边缘比例，圆角按图标比例 22.5%。
    let target = CGRect(x: centerX - edge / 2, y: centerY - edge / 2,
                        width: edge, height: edge)
    let cornerRadius = edge * CGFloat(squircleEdge) / CGFloat(iconCanvas) * 0.225
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: target, cornerWidth: cornerRadius,
                       cornerHeight: cornerRadius, transform: nil))
    ctx.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: iconTop.r, green: iconTop.g, blue: iconTop.b, alpha: 1),
        CGColor(red: iconBottom.r, green: iconBottom.g, blue: iconBottom.b, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors,
                                 locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: target.midX, y: target.maxY),
                               end: CGPoint(x: target.midX, y: target.minY),
                               options: [])
    }
    ctx.restoreGState()

    // 白色标记占图标 64%（与 make-icon.swift 相同）。
    let markEdge = edge * markFraction
    let markRect = CGRect(x: centerX - markEdge / 2, y: centerY - markEdge / 2,
                          width: markEdge, height: markEdge)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(markPath(in: markRect))
    ctx.fillPath()
}

/// 以 CG 基线 y 绘制一串不同颜色的文字，返回结束 x（供光标紧随末字形）。
@discardableResult
func drawText(_ runs: [(String, NSColor)], font: NSFont, x: CGFloat,
              baselineCGY: CGFloat) -> CGFloat {
    var penX = x
    for (text, color) in runs {
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color,
        ])
        attr.draw(at: CGPoint(x: penX, y: baselineCGY))
        penX += attr.size().width
    }
    return penX
}

// MARK: - 位图

func makeContext(widthPx: Int, heightPx: Int, scale: CGFloat) -> (NSBitmapImageRep, CGContext) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: widthPx, pixelsHigh: heightPx,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("无法创建位图") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        fatalError("无图形上下文")
    }
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true
    ctx.scaleBy(x: scale, y: scale)
    return (rep, ctx)
}

func endContext() { NSGraphicsContext.restoreGraphicsState() }

// MARK: - README 主图（设计空间 620×200 pt，顶左原点；@2x 输出 1240×400 px）

func renderHero(dark: Bool) -> NSBitmapImageRep {
    let canvasH: CGFloat = 200
    let (rep, ctx) = makeContext(widthPx: 1240, heightPx: 400, scale: 2)

    let fieldColor = dark ? NSColor(calibratedRed: 0x1B / 255, green: 0x25 / 255,
                                    blue: 0x28 / 255, alpha: 1) : NSColor.white
    let fieldLine = dark ? NSColor(calibratedWhite: 1, alpha: 0.14)
                         : NSColor(calibratedWhite: 0, alpha: 0.12)
    let textColor = dark ? NSColor(calibratedRed: 0xE4 / 255, green: 0xED / 255,
                                   blue: 0xEE / 255, alpha: 1)
                         : NSColor(calibratedRed: 0x2B / 255, green: 0x3A / 255,
                                   blue: 0x3F / 255, alpha: 1)
    let accentColor = NSColor(calibratedRed: accent.r, green: accent.g, blue: accent.b,
                              alpha: 1)

    // 图标：100×100 pt，x=30、y=50（垂直居中）。
    drawIcon(centerX: 30 + 50, centerY: canvasH - 50 - 50, edge: 100, in: ctx)

    // 五根渐显的主题色小柱，垂直居中，位于图标与卡片之间（x 156–218）。
    let columns: [(CGFloat, CGFloat, CGFloat)] = [  // (x, height, alpha)
        (156, 16, 0.35), (170, 40, 0.5), (184, 60, 0.7), (198, 32, 0.85), (212, 48, 1.0),
    ]
    for (x, h, alpha) in columns {
        fillRounded(cgRect(x: x, topY: 100 - h / 2, width: 6, height: h, canvasH: canvasH),
                    radius: 3, color: accentColor, in: ctx, alpha: alpha)
    }

    // 文本输入框卡片：x=240、350×68 pt、圆角 14，垂直居中。
    let card = cgRect(x: 240, topY: 66, width: 350, height: 68, canvasH: canvasH)
    fillRounded(card, radius: 14, color: fieldColor, in: ctx)
    ctx.saveGState()
    ctx.setLineWidth(1.5)
    fieldLine.setStroke()
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: 14, cornerHeight: 14,
                       transform: nil))
    ctx.strokePath()
    ctx.restoreGState()

    // 「按住说话，松手成文。」22 pt，x=264，在卡片内垂直居中。
    let phrase = "按住说话，松手成文。"
    let font = NSFont.systemFont(ofSize: 22, weight: .regular)
    let attr = NSAttributedString(string: phrase, attributes: [.font: font])
    let textHeight = attr.size().height
    let designTopY = 100 - textHeight / 2
    let baselineCG = canvasH - (designTopY + font.ascender)
    let endX = drawText([(phrase, textColor)], font: font, x: 264,
                        baselineCGY: baselineCG)

    // 主题色光标：3×32 pt，紧随末字形，在卡片内垂直居中。
    fillRounded(cgRect(x: endX + 5, topY: 84, width: 3, height: 32, canvasH: canvasH),
                radius: 1.5, color: accentColor, in: ctx)

    endContext()
    return rep
}

// MARK: - 社交预览图（设计空间即 1280×640 px，顶左原点；scale 1）

func renderSocial() -> NSBitmapImageRep {
    let canvasH: CGFloat = 640
    let (rep, ctx) = makeContext(widthPx: 1280, heightPx: 640, scale: 1)

    // 墨底。
    ctx.setFillColor(CGColor(red: ink.r, green: ink.g, blue: ink.b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 1280, height: 640))

    // 右侧淡主题色柱（设计稿同形，几何为像素字面量）。
    let barColor = NSColor(calibratedRed: accentDark.r, green: accentDark.g,
                           blue: accentDark.b, alpha: 1)
    let columns: [(CGFloat, CGFloat, CGFloat)] = [  // (x, topY, height)
        (760, 120, 400), (840, 40, 560), (920, 160, 320), (1000, 90, 460), (1080, 200, 240),
    ]
    for (x, topY, h) in columns {
        fillRounded(cgRect(x: x, topY: topY, width: 44, height: h, canvasH: canvasH),
                    radius: 22, color: barColor, in: ctx, alpha: 0.13)
    }

    // 图标：160×160，x=96、y=140。
    drawIcon(centerX: 96 + 80, centerY: canvasH - 140 - 80, edge: 160, in: ctx)

    let lightText = NSColor(calibratedRed: 0xE4 / 255, green: 0xED / 255,
                            blue: 0xEE / 255, alpha: 1)
    let accentText = NSColor(calibratedRed: accentDark.r, green: accentDark.g,
                             blue: accentDark.b, alpha: 1)
    let dimText = NSColor(calibratedRed: 0x93 / 255, green: 0xA5 / 255,
                          blue: 0xA9 / 255, alpha: 1)

    // 字标、标语（后半句主题色）、英文副题；基线按设计稿顶左原点给出。
    drawText([("MiVibe", lightText)],
             font: NSFont.systemFont(ofSize: 96, weight: .bold),
             x: 96, baselineCGY: cgBaseline(420, canvasH: canvasH))
    drawText([("按住说话，", lightText), ("松手成文。", accentText)],
             font: NSFont.systemFont(ofSize: 40, weight: .regular),
             x: 96, baselineCGY: cgBaseline(492, canvasH: canvasH))
    drawText([("Voice input for macOS with a Bluetooth voice remote", dimText)],
             font: NSFont.systemFont(ofSize: 26, weight: .regular),
             x: 96, baselineCGY: cgBaseline(548, canvasH: canvasH))

    endContext()
    return rep
}

// MARK: - PNG 写出（无元数据，保证字节稳定）

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let cg = rep.cgImage else { fatalError("无法取得 CGImage") }
    try? FileManager.default.removeItem(at: url)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("无法创建 PNG 输出：\(url.path)") }
    CGImageDestinationAddImage(dest, cg, nil)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("PNG 写出失败：\(url.path)")
    }
}

// MARK: - 主流程

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let images = root.appendingPathComponent("docs/images")
try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)

try writePNG(renderHero(dark: false), to: images.appendingPathComponent("hero-light.png"))
try writePNG(renderHero(dark: true), to: images.appendingPathComponent("hero-dark.png"))
try writePNG(renderSocial(), to: images.appendingPathComponent("social-preview.png"))
print("已写出 hero-light.png / hero-dark.png / social-preview.png 到 \(images.path)")
