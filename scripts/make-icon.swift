// Renders the app icon: a white down-arrow into a tray on TorrDroid-style green.
// Usage: swift scripts/make-icon.swift out.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("no context") }
ctx.setFillColor(CGColor(srgbRed: 0x8B / 255.0, green: 0xC3 / 255.0, blue: 0x4A / 255.0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
// Shaft (y grows upwards in Core Graphics).
ctx.fill(CGRect(x: 452, y: 420, width: 120, height: 360))
// Head.
ctx.move(to: CGPoint(x: 262, y: 470))
ctx.addLine(to: CGPoint(x: 762, y: 470))
ctx.addLine(to: CGPoint(x: 512, y: 250))
ctx.closePath()
ctx.fillPath()
// Tray line.
let tray = CGPath(roundedRect: CGRect(x: 232, y: 160, width: 560, height: 70), cornerWidth: 35, cornerHeight: 35, transform: nil)
ctx.addPath(tray)
ctx.fillPath()
guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("no image") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
