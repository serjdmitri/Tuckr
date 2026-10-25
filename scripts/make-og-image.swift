// Makes docs/images/og.png (the picture shown when the site or the repo is shared).
//   swift scripts/make-og-image.swift
import AppKit

let dir = "docs/images/"
func load(_ name: String) -> CGImage {
    NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: dir + name)))!.cgImage!
}
let W = 1200, H = 630
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.04, green: 0.035, blue: 0.075, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
for (c, color) in [(CGPoint(x: 160, y: H), CGColor(red: 0.45, green: 0.22, blue: 0.95, alpha: 0.55)),
                   (CGPoint(x: 1080, y: 0), CGColor(red: 0.98, green: 0.52, blue: 0.2, alpha: 0.45))] {
    let g = CGGradient(colorsSpace: space, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 800, options: [])
}
let notch = load("home.png")
let nw: CGFloat = 1040, nh = nw * CGFloat(notch.height) / CGFloat(notch.width)
ctx.draw(notch, in: CGRect(x: (CGFloat(W) - nw) / 2, y: CGFloat(H) - nh, width: nw, height: nh))
let icon = load("icon.png")
ctx.draw(icon, in: CGRect(x: 90, y: 90, width: 150, height: 150))
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
NSAttributedString(string: "Tuckr", attributes: [.font: NSFont.systemFont(ofSize: 92, weight: .bold), .foregroundColor: NSColor.white])
    .draw(at: CGPoint(x: 270, y: 150))
NSAttributedString(string: "Everything you reach for, tucked into your Mac's notch.", attributes: [.font: NSFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.78)])
    .draw(at: CGPoint(x: 272, y: 100))
NSAttributedString(string: "Free · open source · no telemetry", attributes: [.font: NSFont.systemFont(ofSize: 24, weight: .regular), .foregroundColor: NSColor(white: 1, alpha: 0.55)])
    .draw(at: CGPoint(x: 272, y: 56))
NSGraphicsContext.restoreGraphicsState()
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir + "og.png"))
print("wrote og.png")
