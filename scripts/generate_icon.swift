#!/usr/bin/env swift
// アプリアイコンを生成する。紙の上に栞が 1 本のデザイン。
//   使い方: swift scripts/generate_icon.swift Shiori/Assets.xcassets/AppIcon.appiconset
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // macOS のアイコン枠（1024 のうち 824 の角丸）
    let inset = s * 0.098
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let squircle = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = s * 0.022
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(srgbRed: 0.97, green: 0.95, blue: 0.89, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    // 紙の色
    NSGradient(colors: [
        NSColor(srgbRed: 0.99, green: 0.98, blue: 0.94, alpha: 1),
        NSColor(srgbRed: 0.93, green: 0.89, blue: 0.80, alpha: 1),
    ])!.draw(in: body, angle: -90)

    // 縦書きの行を思わせる細い線
    let lineColor = NSColor(srgbRed: 0.45, green: 0.39, blue: 0.31, alpha: 0.5)
    lineColor.setFill()
    let lineWidth = body.width * 0.022
    let lineTop = body.maxY - body.height * 0.17
    let spacing = body.width * 0.085
    let lengths: [CGFloat] = [0.62, 0.66, 0.5, 0.66]
    for (index, length) in lengths.enumerated() {
        let x = body.minX + body.width * 0.17 + CGFloat(index) * spacing
        let h = body.height * length
        NSBezierPath(roundedRect: NSRect(x: x, y: lineTop - h, width: lineWidth, height: h),
                     xRadius: lineWidth / 2, yRadius: lineWidth / 2).fill()
    }

    // 栞
    let ribbonWidth = body.width * 0.25
    let ribbonX = body.maxX - body.width * 0.16 - ribbonWidth
    let ribbonBottom = body.minY + body.height * 0.2
    let notch = ribbonWidth * 0.42
    let ribbon = NSBezierPath()
    ribbon.move(to: NSPoint(x: ribbonX, y: body.maxY + s * 0.01))
    ribbon.line(to: NSPoint(x: ribbonX + ribbonWidth, y: body.maxY + s * 0.01))
    ribbon.line(to: NSPoint(x: ribbonX + ribbonWidth, y: ribbonBottom))
    ribbon.line(to: NSPoint(x: ribbonX + ribbonWidth / 2, y: ribbonBottom + notch))
    ribbon.line(to: NSPoint(x: ribbonX, y: ribbonBottom))
    ribbon.close()
    let ribbonShadow = NSShadow()
    ribbonShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    ribbonShadow.shadowBlurRadius = s * 0.012
    ribbonShadow.shadowOffset = NSSize(width: -s * 0.004, height: -s * 0.004)
    NSGraphicsContext.saveGraphicsState()
    ribbonShadow.set()
    NSColor(srgbRed: 0.62, green: 0.16, blue: 0.18, alpha: 1).setFill()
    ribbon.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [
        NSColor(srgbRed: 0.72, green: 0.20, blue: 0.21, alpha: 1),
        NSColor(srgbRed: 0.56, green: 0.13, blue: 0.16, alpha: 1),
    ])!.draw(in: ribbon, angle: -90)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count > 1 else {
    print("使い方: swift scripts/generate_icon.swift <AppIcon.appiconset>")
    exit(1)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try! render(size: size).write(to: folder.appendingPathComponent("icon_\(size).png"))
}
