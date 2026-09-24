import AppKit
import Foundation

// Procedural app mark; no downloaded images, bundled fonts, or external artwork.
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func draw(size: Int) throws -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let rect = NSRect(x: 50, y: 50, width: 924, height: 924)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.06, green: 0.20, blue: 0.25, alpha: 1),
                              ending: NSColor(srgbRed: 0.04, green: 0.48, blue: 0.44, alpha: 1))!
    gradient.draw(in: shape, angle: 60)
    NSColor(srgbRed: 0.75, green: 0.99, blue: 0.88, alpha: 1).setStroke()
    let trunk = NSBezierPath(); trunk.lineWidth = 39; trunk.lineCapStyle = .round
    trunk.move(to: NSPoint(x: 240, y: 365)); trunk.line(to: NSPoint(x: 770, y: 365))
    trunk.move(to: NSPoint(x: 390, y: 365))
    trunk.curve(to: NSPoint(x: 735, y: 690), controlPoint1: NSPoint(x: 555, y: 365), controlPoint2: NSPoint(x: 540, y: 690))
    trunk.stroke()
    for point in [NSPoint(x: 240,y:365), NSPoint(x:390,y:365), NSPoint(x:770,y:365), NSPoint(x:735,y:690)] {
        NSColor(srgbRed: 0.84, green: 1, blue: 0.93, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x-45,y:point.y-45,width:90,height:90)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for dimension in [16, 32, 128, 256, 512] {
    try draw(size: dimension).write(to: folder.appendingPathComponent("icon_\(dimension)x\(dimension).png"))
    try draw(size: dimension * 2).write(to: folder.appendingPathComponent("icon_\(dimension)x\(dimension)@2x.png"))
}
