// Draws the picture behind the icons in Tuckr's installer window (660 x 400 points, drawn at 2x).
//   swift scripts/make-dmg-background.swift out.png
import AppKit

let out = CommandLine.arguments[1]
let W = 660, H = 400, S = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W * S, pixelsHigh: H * S, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)   // 144 dpi: Finder shows it at 660 x 400 points
NSGraphicsContext.saveGraphicsState()
let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsctx
let ctx = nsctx.cgContext
let space = CGColorSpaceCreateDeviceRGB()

// A light page, so the icon names stay readable in light and dark mode.
let base = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.985, green: 0.98, blue: 1, alpha: 1),
                                                    CGColor(red: 0.925, green: 0.915, blue: 0.985, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: 0, y: 0), options: [])
for (c, color) in [(CGPoint(x: 40, y: CGFloat(H)), CGColor(red: 0.48, green: 0.36, blue: 1, alpha: 0.30)),
                   (CGPoint(x: CGFloat(W) - 20, y: 0), CGColor(red: 1, green: 0.54, blue: 0.3, alpha: 0.26))] {
    let g = CGGradient(colorsSpace: space, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 330, options: [])
}

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerX: CGFloat, baselineY: CGFloat) {
    let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    a.draw(at: CGPoint(x: centerX - a.size().width / 2, y: baselineY))
}
// Coordinates are bottom-up here; the icons sit at y = 190 from the top, i.e. 210 from the bottom.
text("Install Tuckr", size: 30, weight: .bold, color: NSColor(red: 0.12, green: 0.09, blue: 0.22, alpha: 1), centerX: CGFloat(W) / 2, baselineY: 330)
text("Drag Tuckr into your Applications folder", size: 15, weight: .regular, color: NSColor(red: 0.36, green: 0.33, blue: 0.5, alpha: 1), centerX: CGFloat(W) / 2, baselineY: 304)

// The arrow between the two icons.
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 262, y: 214))
arrow.addCurve(to: CGPoint(x: 398, y: 214), control1: CGPoint(x: 300, y: 262), control2: CGPoint(x: 360, y: 262))
ctx.setStrokeColor(CGColor(red: 0.48, green: 0.36, blue: 1, alpha: 0.95))
ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.setLineDash(phase: 0, lengths: [1, 10])
ctx.addPath(arrow); ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
ctx.setLineWidth(5)
let head = CGMutablePath()
head.move(to: CGPoint(x: 385, y: 226)); head.addLine(to: CGPoint(x: 402, y: 212)); head.addLine(to: CGPoint(x: 383, y: 202))
ctx.addPath(head); ctx.strokePath()

text("First time: right-click Tuckr, choose Open, then Open.  Updates install themselves after that.", size: 12, weight: .medium,
     color: NSColor(red: 0.42, green: 0.39, blue: 0.56, alpha: 1), centerX: CGFloat(W) / 2, baselineY: 36)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
