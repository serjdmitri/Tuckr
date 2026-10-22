// Renders The BoringCoucouify's app icon into the asset catalog.
//
//   swiftc -O scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon boringNotch/Assets.xcassets/AppIcon.appiconset
//
// A dark macOS icon with a warm glow, and a notch hanging from the top edge
// that carries three dots: dictation, call notes and agents.
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

  let base = CGGradient(
    colorsSpace: space, colors: [color(0x20232D), color(0x090A0E)] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(
    base, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

  func glow(_ center: CGPoint, _ radius: CGFloat, _ stops: [(UInt32, CGFloat)]) {
    let g = CGGradient(
      colorsSpace: space, colors: stops.map { color($0.0, $0.1) } as CFArray,
      locations: stops.indices.map { CGFloat($0) / CGFloat(stops.count - 1) })!
    ctx.drawRadialGradient(
      g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
  }
  glow(CGPoint(x: 470, y: 250), 560, [(0xFB923C, 0.95), (0xF0603A, 0.55), (0x8B5CF6, 0.28), (0x8B5CF6, 0)])
  glow(CGPoint(x: 800, y: 560), 380, [(0x3B9EFF, 0.40), (0x3B9EFF, 0)])

  // Two translucent cards, the shape of the Agents tab.
  for x in [176.0, 530.0] {
    let card = CGPath(
      roundedRect: CGRect(x: x, y: 238, width: 318, height: 214), cornerWidth: 56, cornerHeight: 56,
      transform: nil)
    ctx.addPath(card)
    ctx.setFillColor(color(0x000000, 0.34))
    ctx.fillPath()
    ctx.addPath(card)
    ctx.setStrokeColor(color(0xFFFFFF, 0.14))
    ctx.setLineWidth(5)
    ctx.strokePath()
  }

  // The notch, hanging from the top edge.
  let notchW: CGFloat = 400, notchH: CGFloat = 170, radius: CGFloat = 80
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

  // The three dots in the notch.
  let dots: [(CGFloat, UInt32)] = [(412, 0x3B9EFF), (512, 0x34D399), (612, 0xFB923C)]
  for (x, hex) in dots {
    let rect = CGRect(x: x - 27, y: bottom + notchH / 2 - 27 - 6, width: 54, height: 54)
    ctx.setFillColor(color(hex))
    ctx.fillEllipse(in: rect)
    ctx.setFillColor(color(0xFFFFFF, 0.35))
    ctx.fillEllipse(in: CGRect(x: rect.minX + 12, y: rect.maxY - 22, width: 16, height: 10))
  }
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
