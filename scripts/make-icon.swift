import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let p = CGFloat(pixels)
        let tile = NSBezierPath(roundedRect: NSRect(x: p * 0.08, y: p * 0.08, width: p * 0.84, height: p * 0.84), xRadius: p * 0.23, yRadius: p * 0.23)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = p * 0.035
        shadow.shadowOffset = NSSize(width: 0, height: -p * 0.02)
        shadow.set()
        NSColor(calibratedRed: 0.06, green: 0.12, blue: 0.13, alpha: 1).setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.22, blue: 0.23, alpha: 1),
                   ending: NSColor(calibratedRed: 0.06, green: 0.12, blue: 0.13, alpha: 1))!.draw(in: tile, angle: -45)
        NSColor.white.withAlphaComponent(0.12).setStroke()
        tile.lineWidth = max(0.5, p * 0.002)
        tile.stroke()
        let colors = [NSColor(calibratedRed: 0.77, green: 0.43, blue: 0.30, alpha: 1), NSColor(calibratedRed: 0.16, green: 0.57, blue: 0.48, alpha: 1)]
        for (index, height) in [0.36, 0.55].enumerated() {
            colors[index].setFill()
            NSBezierPath(roundedRect: NSRect(x: p * (0.27 + Double(index) * 0.27), y: p * 0.25, width: p * 0.19, height: p * height), xRadius: p * 0.055, yRadius: p * 0.055).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
