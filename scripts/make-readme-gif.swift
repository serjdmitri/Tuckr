// Makes docs/images/showcase.gif from snapshots of the notch's own window (PNG, with transparency).
//   swift scripts/make-readme-gif.swift out.gif "frame1.png|Caption one" "frame2.png|Caption two" ...
// Each frame is held for a moment and cross-faded into the next one.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())
let out = args[0]
let items: [(CGImage, String)] = args.dropFirst().map { arg in
    let parts = arg.components(separatedBy: "|")
    let data = try! Data(contentsOf: URL(fileURLWithPath: parts[0]))
    return (NSBitmapImageRep(data: data)!.cgImage!, parts.count > 1 ? parts[1] : "")
}

let canvasW = 800
let scale = CGFloat(canvasW) / 1400 * 0.9
let tallest = items.map { CGFloat($0.0.height) * scale }.max()!
let canvasH = Int(tallest) + 70
let space = CGColorSpaceCreateDeviceRGB()

func compose(_ item: (CGImage, String)) -> CGImage {
    let ctx = CGContext(data: nil, width: canvasW, height: canvasH, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.055, green: 0.047, blue: 0.095, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
    let glows: [(CGPoint, CGColor)] = [
        (CGPoint(x: CGFloat(canvasW) * 0.12, y: CGFloat(canvasH)), CGColor(red: 0.45, green: 0.22, blue: 0.95, alpha: 0.38)),
        (CGPoint(x: CGFloat(canvasW) * 0.92, y: 0), CGColor(red: 0.98, green: 0.52, blue: 0.2, alpha: 0.30)),
    ]
    for (c, color) in glows {
        let g = CGGradient(colorsSpace: space, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(canvasW) * 0.7, options: [])
    }
    let w = CGFloat(item.0.width) * scale, h = CGFloat(item.0.height) * scale
    ctx.draw(item.0, in: CGRect(x: (CGFloat(canvasW) - w) / 2, y: CGFloat(canvasH) - h, width: w, height: h))
    let text = NSAttributedString(string: item.1, attributes: [
        .font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.82)])
    let size = text.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    text.draw(at: CGPoint(x: (CGFloat(canvasW) - size.width) / 2, y: 22))
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

func blend(_ a: CGImage, _ b: CGImage, _ t: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: canvasW, height: canvasH, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let r = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)
    ctx.draw(a, in: r)
    ctx.setAlpha(t)
    ctx.draw(b, in: r)
    return ctx.makeImage()!
}

let composed = items.map(compose)
var frames: [(CGImage, Double)] = []
for (i, image) in composed.enumerated() {
    frames.append((image, i == 0 ? 2.6 : 2.4))
    let next = composed[(i + 1) % composed.count]
    for step in 1...3 { frames.append((blend(image, next, CGFloat(step) / 4), 0.07)) }
}

let url = URL(fileURLWithPath: out) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (image, delay) in frames {
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
}
precondition(CGImageDestinationFinalize(dest))
print("wrote \(out): \(frames.count) frames, \(canvasW)x\(canvasH)")
