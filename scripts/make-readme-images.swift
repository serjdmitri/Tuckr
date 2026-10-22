// Composes docs/images/hero.png and docs/images/tabs.png from the four window
// captures in docs/images (home, shelf, agents, meetings).
//   swift scripts/make-readme-images.swift
import AppKit

let dir = "docs/images/"

func load(_ name: String) -> CGImage {
    let data = try! Data(contentsOf: URL(fileURLWithPath: dir + name + ".png"))
    return NSBitmapImageRep(data: data)!.cgImage!
}

func backdrop(_ ctx: CGContext, _ rect: CGRect, hue: Int) {
    let space = CGColorSpaceCreateDeviceRGB()
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.setFillColor(CGColor(red: 0.07, green: 0.06, blue: 0.12, alpha: 1))
    ctx.fill(rect)
    let glows: [(CGPoint, CGColor)] = hue == 0
        ? [(CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY), CGColor(red: 0.45, green: 0.22, blue: 0.95, alpha: 0.85)),
           (CGPoint(x: rect.minX + rect.width * 0.9, y: rect.minY), CGColor(red: 0.98, green: 0.52, blue: 0.2, alpha: 0.8))]
        : [(CGPoint(x: rect.minX + rect.width * 0.85, y: rect.maxY), CGColor(red: 0.98, green: 0.45, blue: 0.3, alpha: 0.7)),
           (CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY), CGColor(red: 0.4, green: 0.25, blue: 0.95, alpha: 0.8))]
    for (center, color) in glows {
        let g = CGGradient(colorsSpace: space, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center,
                               endRadius: max(rect.width, rect.height) * 0.75, options: [])
    }
    ctx.restoreGState()
}

/// The capture is the notch window: its content hangs from the top edge.
func place(_ ctx: CGContext, _ img: CGImage, inTile tile: CGRect, width: CGFloat) {
    let h = width * CGFloat(img.height) / CGFloat(img.width)
    ctx.draw(img, in: CGRect(x: tile.midX - width / 2, y: tile.maxY - h, width: width, height: h))
}

func render(size: CGSize, _ body: (CGContext) -> Void, to name: String) {
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    body(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir + name + ".png"))
}

render(size: CGSize(width: 1600, height: 340), { ctx in
    let full = CGRect(x: 0, y: 0, width: 1600, height: 340)
    backdrop(ctx, full, hue: 0)
    place(ctx, load("agents"), inTile: full, width: 1120)
}, to: "hero")

let names = ["home", "shelf", "agents", "meetings"]
let tileW: CGFloat = 800, tileH: CGFloat = 250
render(size: CGSize(width: tileW * 2, height: tileH * 2), { ctx in
    for (i, name) in names.enumerated() {
        let tile = CGRect(x: CGFloat(i % 2) * tileW, y: CGFloat(1 - i / 2) * tileH, width: tileW, height: tileH)
        backdrop(ctx, tile, hue: (i + i / 2) % 2)
        place(ctx, load(name), inTile: tile, width: 700)
    }
}, to: "tabs")
