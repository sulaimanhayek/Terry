// Draws App/AppIcon.icns. Run with `make icon`.
import AppKit

func draw(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    // macOS icon grid: an 824 pt rounded square centered on a 1024 pt canvas.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                            xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(red: 0.36, green: 0.42, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.22, green: 0.16, blue: 0.72, alpha: 1))!.draw(in: tile, angle: -90)
    NSColor.white.setFill()
    let heights: [CGFloat] = [180, 340, 500, 300, 420, 220]
    let bar: CGFloat = 56, gap: CGFloat = 40
    var x = 512 - (CGFloat(heights.count) * bar + CGFloat(heights.count - 1) * gap) / 2
    for h in heights {
        NSBezierPath(roundedRect: NSRect(x: x * s, y: (512 - h / 2) * s, width: bar * s, height: h * s),
                     xRadius: bar / 2 * s, yRadius: bar / 2 * s).fill()
        x += bar + gap
    }
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(filePath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try draw(size: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try draw(size: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
let iconutil = try Process.run(URL(filePath: "/usr/bin/iconutil"), arguments: ["-c", "icns", iconset.path, "-o", "App/AppIcon.icns"])
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
