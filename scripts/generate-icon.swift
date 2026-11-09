// Renders the KeepMeAlive app icon: a closed laptop under a night sky, with a
// glowing heartbeat line rising out of it — the lid is shut, the work is alive.
//
// Usage: swift scripts/generate-icon.swift <output.png>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Flip so y grows downward, like a design canvas.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// macOS icon grid: 824 pt body centred on a 1024 canvas, ~185 pt corner radius.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x000000, 0.35))
ctx.addPath(squircle); ctx.setFillColor(rgb(0x0B1226)); ctx.fillPath()
ctx.restoreGState()

// Night-sky gradient.
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let sky = CGGradient(colorsSpace: cs, colors: [rgb(0x23356B), rgb(0x141F45), rgb(0x080D1F)] as CFArray,
                     locations: [0, 0.55, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

// Soft glow behind the pulse.
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0x3DF5B5, 0.30), rgb(0x3DF5B5, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 560), endRadius: 380, options: [])

// Stars.
let stars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (230, 250, 7, 0.9), (330, 190, 4, 0.6), (420, 300, 5, 0.7), (760, 420, 4, 0.55),
    (205, 410, 4, 0.5), (590, 210, 5, 0.65), (840, 300, 3, 0.5), (300, 470, 3, 0.4),
]
for (x, y, r, a) in stars {
    ctx.setFillColor(rgb(0xFFFFFF, a))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// Crescent moon (top right): disc A minus an offset disc B.
let moonDisc = CGRect(x: 640, y: 170, width: 180, height: 180)
let bite = CGRect(x: 690, y: 135, width: 170, height: 170)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 46, color: rgb(0xFFE7A3, 0.6))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.addEllipse(in: moonDisc)
ctx.clip()
let cut = CGMutablePath()
cut.addRect(moonDisc.insetBy(dx: -10, dy: -10))
cut.addEllipse(in: bite)
ctx.addPath(cut)
ctx.setFillColor(rgb(0xFFE29A))
ctx.fillPath(using: .evenOdd)
ctx.endTransparencyLayer()
ctx.restoreGState()

// Closed laptop: a slim lid slab on a slightly wider base, seen from the front.
let lid = CGPath(roundedRect: CGRect(x: 250, y: 700, width: 524, height: 46), cornerWidth: 18, cornerHeight: 18, transform: nil)
let laptopFill = CGGradient(colorsSpace: cs, colors: [rgb(0xC9D3E8), rgb(0x8994B0)] as CFArray, locations: [0, 1])!
ctx.saveGState()
ctx.addPath(lid); ctx.clip()
ctx.drawLinearGradient(laptopFill, start: CGPoint(x: 0, y: 700), end: CGPoint(x: 0, y: 746), options: [])
ctx.restoreGState()
let base = CGPath(roundedRect: CGRect(x: 210, y: 746, width: 604, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil)
ctx.saveGState()
ctx.addPath(base); ctx.clip()
ctx.drawLinearGradient(laptopFill, start: CGPoint(x: 0, y: 746), end: CGPoint(x: 0, y: 776), options: [])
ctx.restoreGState()
// Thumb notch on the base.
ctx.setFillColor(rgb(0x5A6585))
ctx.fill(CGRect(x: 462, y: 746, width: 100, height: 8))

// Heartbeat line rising out of the closed lid.
let pulse = CGMutablePath()
pulse.move(to: CGPoint(x: 205, y: 600))
pulse.addLine(to: CGPoint(x: 375, y: 600))
pulse.addLine(to: CGPoint(x: 420, y: 520))
pulse.addLine(to: CGPoint(x: 478, y: 680))
pulse.addLine(to: CGPoint(x: 548, y: 390))
pulse.addLine(to: CGPoint(x: 610, y: 640))
pulse.addLine(to: CGPoint(x: 650, y: 600))
pulse.addLine(to: CGPoint(x: 819, y: 600))

// Soft neon glow: the same stroke twice with a wide blurred shadow.
for blur in [CGFloat(60), 26] {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: blur, color: rgb(0x3DF5B5, 0.95))
    ctx.addPath(pulse)
    ctx.setStrokeColor(rgb(0x2EE6A6))
    ctx.setLineWidth(22); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}
// Crisp core with a mint-to-white gradient.
ctx.saveGState()
ctx.addPath(pulse)
ctx.setLineWidth(22); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.replacePathWithStrokedPath()
ctx.clip()
let core = CGGradient(colorsSpace: cs, colors: [rgb(0x2EE6A6), rgb(0xE9FFF7), rgb(0x2EE6A6)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(core, start: CGPoint(x: 205, y: 0), end: CGPoint(x: 819, y: 0), options: [])
ctx.restoreGState()

// Subtle top highlight for depth.
let sheen = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 420), options: [])
ctx.restoreGState()

// Hairline edge.
ctx.addPath(squircle)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.08)); ctx.setLineWidth(2); ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
