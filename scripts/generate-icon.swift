import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for (name, size) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
    NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.22, blue: 0.15, alpha: 1),
               ending: NSColor(calibratedRed: 0.13, green: 0.08, blue: 0.06, alpha: 1))!
        .draw(in: tile, angle: -60)
    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    tile.lineWidth = 3
    tile.stroke()
    let cream = NSColor(calibratedRed: 1, green: 0.91, blue: 0.79, alpha: 1)
    cream.setStroke()
    let handle = NSBezierPath(roundedRect: NSRect(x: 641, y: 396, width: 148, height: 154), xRadius: 63, yRadius: 63)
    handle.lineWidth = 39
    handle.stroke()
    cream.setFill()
    let cup = NSBezierPath()
    cup.move(to: NSPoint(x: 279, y: 608))
    cup.line(to: NSPoint(x: 681, y: 608))
    cup.line(to: NSPoint(x: 666, y: 410))
    cup.curve(to: NSPoint(x: 576, y: 325), controlPoint1: NSPoint(x: 663, y: 355), controlPoint2: NSPoint(x: 630, y: 325))
    cup.line(to: NSPoint(x: 385, y: 325))
    cup.curve(to: NSPoint(x: 295, y: 410), controlPoint1: NSPoint(x: 331, y: 325), controlPoint2: NSPoint(x: 299, y: 355))
    cup.close()
    cup.fill()
    let saucer = NSBezierPath()
    saucer.lineWidth = 24
    saucer.lineCapStyle = .round
    saucer.move(to: NSPoint(x: 254, y: 275))
    saucer.curve(to: NSPoint(x: 731, y: 275), controlPoint1: NSPoint(x: 358, y: 233), controlPoint2: NSPoint(x: 627, y: 233))
    saucer.stroke()
    let steam = NSBezierPath()
    steam.lineWidth = 23
    steam.lineCapStyle = .round
    for x: CGFloat in [397, 505, 613] {
        steam.move(to: NSPoint(x: x, y: 672))
        steam.curve(to: NSPoint(x: x, y: 796), controlPoint1: NSPoint(x: x - 45, y: 718), controlPoint2: NSPoint(x: x + 45, y: 750))
    }
    steam.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination + "/" + name + ".png"))
}
