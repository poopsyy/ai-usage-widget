import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.09, green: 0.16, blue: 0.17, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88), xRadius: p * 0.21, yRadius: p * 0.21).fill()
        let colors = [NSColor(calibratedRed: 0.83, green: 0.51, blue: 0.36, alpha: 1), NSColor(calibratedRed: 0.32, green: 0.77, blue: 0.64, alpha: 1)]
        for (index, height) in [0.36, 0.55].enumerated() {
            colors[index].setFill()
            NSBezierPath(roundedRect: NSRect(x: p * (0.27 + Double(index) * 0.27), y: p * 0.25, width: p * 0.19, height: p * height), xRadius: p * 0.055, yRadius: p * 0.055).fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
