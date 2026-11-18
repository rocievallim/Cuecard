import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let canvas = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                       bytesPerRow: 0, space: space,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let tile = CGPath(roundedRect: CGRect(x: 90, y: 90, width: 844, height: 844),
                  cornerWidth: 189, cornerHeight: 189, transform: nil)

canvas.saveGState()
canvas.addPath(tile)
canvas.clip()
let colors = [CGColor(red: 0.06, green: 0.14, blue: 0.23, alpha: 1),
              CGColor(red: 0.18, green: 0.32, blue: 0.46, alpha: 1)]
let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
canvas.drawLinearGradient(gradient, start: CGPoint(x: 830, y: 100),
                          end: CGPoint(x: 190, y: 930), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
canvas.restoreGState()

let card = CGPath(roundedRect: CGRect(x: 262, y: 293, width: 500, height: 438),
                  cornerWidth: 67, cornerHeight: 67, transform: nil)
canvas.setShadow(offset: CGSize(width: 0, height: -14), blur: 24,
                 color: CGColor(gray: 0, alpha: 0.23))
canvas.addPath(card)
canvas.setFillColor(CGColor(red: 0.92, green: 0.96, blue: 1, alpha: 1))
canvas.fillPath()
canvas.setShadow(offset: .zero, blur: 0, color: nil)

for (y, width, alpha) in [(596.0, 241.0, 0.92), (502.0, 313.0, 0.56), (408.0, 181.0, 0.56)] {
    let line = CGPath(roundedRect: CGRect(x: 355, y: y, width: width, height: 31),
                      cornerWidth: 15.5, cornerHeight: 15.5, transform: nil)
    canvas.addPath(line)
    canvas.setFillColor(CGColor(red: 0.13, green: 0.27, blue: 0.43, alpha: alpha))
    canvas.fillPath()
}

func field(_ number: Int) -> Data {
    var value = UInt32(number).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

let master = canvas.makeImage()!
var representations = Data()
for (tag, pixels) in [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
                      ("ic08", 256), ("ic09", 512), ("ic10", 1024)] {
    let image: CGImage
    if pixels == size {
        image = master
    } else {
        let scaled = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                               bytesPerRow: 0, space: space, bitmapInfo: canvas.bitmapInfo.rawValue)!
        scaled.interpolationQuality = .high
        scaled.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        image = scaled.makeImage()!
    }
    let png = NSMutableData()
    let writer = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, image, nil)
    precondition(CGImageDestinationFinalize(writer))
    representations.append(Data(tag.utf8))
    representations.append(field(8 + png.length))
    representations.append(png as Data)
}
let icon = Data("icns".utf8) + field(8 + representations.count) + representations
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
