import Cocoa

// Рисует иконку 1024x1024 в PNG: окно, сворачивающееся в Dock.
// Запуск: swift makeicon.swift out.png

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rrect(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

// Фон: скруглённый квадрат по сетке macOS (отступ 100 px, радиус ~185).
let base = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = rrect(base, 185)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.black.setFill()
bg.fill()
NSGraphicsContext.current?.restoreGraphicsState()

NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.55, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.40, green: 0.25, blue: 0.85, alpha: 1),
])!.draw(in: bg, angle: -60)

bg.addClip()

// Окно (уже наполовину «уехавшее» вниз): светлая карточка с заголовком.
let win = NSRect(x: 250, y: 400, width: 524, height: 360)
NSColor.white.withAlphaComponent(0.95).setFill()
rrect(win, 40).fill()
NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
rrect(NSRect(x: win.minX, y: win.maxY - 84, width: win.width, height: 84), 40).fill()
NSRect(x: win.minX, y: win.maxY - 84, width: win.width, height: 44).fill()
let dots: [NSColor] = [
    NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.18, alpha: 1),
    NSColor(calibratedRed: 0.16, green: 0.79, blue: 0.25, alpha: 1),
]
for (i, c) in dots.enumerated() {
    c.setFill()
    NSBezierPath(ovalIn: NSRect(x: win.minX + 34 + CGFloat(i) * 46, y: win.maxY - 58, width: 30, height: 30)).fill()
}

// Стрелка вниз.
let arrow = NSBezierPath()
arrow.lineWidth = 46
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 432, y: 350))
arrow.line(to: NSPoint(x: 512, y: 270))
arrow.line(to: NSPoint(x: 592, y: 350))
NSColor.white.setStroke()
arrow.stroke()

// Dock: полупрозрачная плашка с иконками.
let dock = NSRect(x: 210, y: 150, width: 604, height: 96)
NSColor.white.withAlphaComponent(0.28).setFill()
rrect(dock, 40).fill()
for i in 0..<4 {
    let item = NSRect(x: dock.minX + 38 + CGFloat(i) * 134, y: dock.minY + 18, width: 60, height: 60)
    NSColor.white.withAlphaComponent(i == 1 ? 0.95 : 0.55).setFill()
    rrect(item, 16).fill()
}

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
