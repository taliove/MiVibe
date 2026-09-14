// Generates the MiVibe app icon: deep blue gradient squircle + white mic symbol.
// Usage: swift Scripts/make-icon.swift
// Output: Sources/MiVibe/Resources/AppIcon.icns (committed; build-app.sh copies it into the bundle).
import AppKit

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func render(_ px: Int) -> NSImage {
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size)
    image.lockFocus()

    let s = CGFloat(px)
    // macOS Big Sur+ icon geometry: artwork sits on an inset squircle (~82% of canvas).
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225

    NSGraphicsContext.current?.imageInterpolation = .high

    // Drop shadow under the squircle.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.set()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Vertical gradient: deep blue → indigo.
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.35, blue: 0.85, alpha: 1),
        NSColor(calibratedRed: 0.28, green: 0.20, blue: 0.72, alpha: 1),
    ])!
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    gradient.draw(in: squircle, angle: -90)

    // White mic symbol, centered, ~52% of the squircle.
    // SF Symbol 的上色必须走 SymbolConfiguration(paletteColors:)，
    // 在上下文里 set() 颜色对它无效。
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: rect.width * 0.52, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let micSize = mic.size
        let symbolRect = NSRect(
            x: rect.midX - micSize.width / 2,
            y: rect.midY - micSize.height / 2,
            width: micSize.width,
            height: micSize.height
        )
        mic.draw(in: symbolRect, from: .init(origin: .zero, size: micSize),
                 operation: .sourceOver, fraction: 1)
    }

    image.unlockFocus()
    return image
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, px) in sizes {
    let image = render(px)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { fatalError("render failed at \(px)") }
    try png.write(to: iconset.appendingPathComponent(name))
}

print("iconset written to \(iconset.path)")
print("run: iconutil -c icns \(iconset.path) -o Sources/MiVibe/Resources/AppIcon.icns")
