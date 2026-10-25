// Renders Tuckr's app icon into the asset catalog.
//
//   swiftc -O scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon boringNotch/Assets.xcassets/AppIcon.appiconset
//
// A dark macOS icon: the notch hangs from the top edge and throws a spotlight onto a small
// purple tile with a winking face, standing on a pink-violet glow.
import AppKit
import CoreGraphics

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha
  )
}

func render(pixels: Int) -> Data {
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let ctx = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.interpolationQuality = .high
  ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

  let body = CGRect(x: 100, y: 100, width: 824, height: 824)
  let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

  // Soft shadow under the body.
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.4))
  ctx.addPath(bodyPath)
  ctx.setFillColor(color(0x12141A))
  ctx.fillPath()
  ctx.restoreGState()

  // Everything else is clipped to the body.
  ctx.saveGState()
  ctx.addPath(bodyPath)
  ctx.clip()

  func gradient(_ stops: [(UInt32, CGFloat)]) -> CGGradient {
    CGGradient(
      colorsSpace: space, colors: stops.map { color($0.0, $0.1) } as CFArray,
      locations: stops.indices.map { CGFloat($0) / CGFloat(stops.count - 1) })!
  }

  ctx.drawLinearGradient(
    gradient([(0x232842, 1), (0x0A0B12, 1)]),
    start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

  // The glow on the floor.
  ctx.saveGState()
  ctx.translateBy(x: 512, y: 215)
  ctx.scaleBy(x: 1, y: 0.42)
  ctx.drawRadialGradient(
    gradient([(0xFF7ACD, 0.95), (0xB55BFF, 0.65), (0x6E47FF, 0.0)]),
    startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 470, options: [])
  ctx.restoreGState()

  // The spotlight from the notch.
  let cone = CGMutablePath()
  cone.move(to: CGPoint(x: 512 - 150, y: 780))
  cone.addLine(to: CGPoint(x: 512 + 150, y: 780))
  cone.addLine(to: CGPoint(x: 512 + 390, y: 215))
  cone.addLine(to: CGPoint(x: 512 - 390, y: 215))
  cone.closeSubpath()
  ctx.saveGState()
  ctx.addPath(cone)
  ctx.clip()
  ctx.drawLinearGradient(
    gradient([(0xFFF3E6, 0.62), (0xFFD9F0, 0.20), (0xFFFFFF, 0.0)]),
    start: CGPoint(x: 512, y: 780), end: CGPoint(x: 512, y: 215), options: [])
  ctx.restoreGState()

  // The tile, with a winking face.
  let tile = CGRect(x: 512 - 128, y: 290, width: 256, height: 256)
  let tilePath = CGPath(roundedRect: tile, cornerWidth: 66, cornerHeight: 66, transform: nil)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: color(0x1A0B4A, 0.65))
  ctx.addPath(tilePath)
  ctx.setFillColor(color(0x6A47F0))
  ctx.fillPath()
  ctx.restoreGState()
  ctx.saveGState()
  ctx.addPath(tilePath)
  ctx.clip()
  ctx.drawLinearGradient(
    gradient([(0x9B73FF, 1), (0x5636D8, 1)]),
    start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
  ctx.restoreGState()
  ctx.addPath(tilePath)
  ctx.setStrokeColor(color(0xFFFFFF, 0.25))
  ctx.setLineWidth(3)
  ctx.strokePath()

  ctx.setFillColor(color(0xFFFFFF))
  ctx.fillEllipse(in: CGRect(x: 512 - 52 - 17, y: 438 - 17, width: 34, height: 34))
  ctx.setStrokeColor(color(0xFFFFFF))
  ctx.setLineWidth(13)
  ctx.setLineCap(.round)
  ctx.addArc(center: CGPoint(x: 512 + 52, y: 432), radius: 22, startAngle: .pi * 0.12, endAngle: .pi * 0.88, clockwise: false)
  ctx.strokePath()
  let mouth = CGMutablePath()
  mouth.addArc(center: CGPoint(x: 512, y: 392), radius: 62, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
  mouth.closeSubpath()
  ctx.addPath(mouth)
  ctx.setFillColor(color(0xFFFFFF))
  ctx.fillPath()
  ctx.saveGState()
  ctx.addPath(mouth)
  ctx.clip()
  ctx.setFillColor(color(0xFF6F9D))
  ctx.fillEllipse(in: CGRect(x: 512 - 34, y: 392 - 80, width: 68, height: 56))
  ctx.restoreGState()

  // The notch, hanging from the top edge.
  let notchW: CGFloat = 330, notchH: CGFloat = 150, radius: CGFloat = 72
  let left = 512 - notchW / 2, top: CGFloat = 924, bottom = top - notchH
  let notch = CGMutablePath()
  notch.move(to: CGPoint(x: left, y: top + 2))
  notch.addLine(to: CGPoint(x: left, y: bottom + radius))
  notch.addArc(
    tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left + radius, y: bottom),
    radius: radius)
  notch.addLine(to: CGPoint(x: left + notchW - radius, y: bottom))
  notch.addArc(
    tangent1End: CGPoint(x: left + notchW, y: bottom),
    tangent2End: CGPoint(x: left + notchW, y: bottom + radius), radius: radius)
  notch.addLine(to: CGPoint(x: left + notchW, y: top + 2))
  notch.closeSubpath()
  ctx.addPath(notch)
  ctx.setFillColor(color(0x000000))
  ctx.fillPath()
  ctx.restoreGState()

  // A faint rim light on the body edge.
  ctx.addPath(bodyPath)
  ctx.setStrokeColor(color(0xFFFFFF, 0.10))
  ctx.setLineWidth(4)
  ctx.strokePath()

  let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
  return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
// (points, scale) pairs the macOS icon set asks for.
let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in slots {
  let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
  try! render(pixels: points * scale).write(to: dir.appendingPathComponent(name))
  images.append([
    "filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)",
  ])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(
  withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: dir.appendingPathComponent("Contents.json"))
print("wrote \(slots.count) icons")
