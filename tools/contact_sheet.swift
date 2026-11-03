// Contact sheet for the README: one frame through every stock, four across, name under each.
//   swift tools/contact_sheet.swift out.jpg "LABEL=path.jpg" ...
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { print("usage: contact_sheet out.jpg LABEL=photo.jpg ..."); exit(2) }
let out = URL(fileURLWithPath: args[0])
let tiles = args.dropFirst().map { a -> (String, URL) in
    let p = a.split(separator: "=", maxSplits: 1).map(String.init)
    return (p[0], URL(fileURLWithPath: p[1]))
}

let cols = 4, tw = 360, th = 240, bar = 34
let rows = (tiles.count + cols - 1) / cols
let w = cols * tw, h = rows * (th + bar)
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.08, blue: 0.08, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
ctx.interpolationQuality = .high
let font = CTFontCreateWithName("Menlo-Regular" as CFString, 20, nil)

for (i, (label, url)) in tiles.enumerated() {
    let x = (i % cols) * tw, top = (i / cols) * (th + bar)
    let y = h - top - th                                   // CG origin is bottom-left
    if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
       let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
        // fill the tile, cropping the long side
        let s = max(Double(tw) / Double(img.width), Double(th) / Double(img.height))
        let dw = Double(img.width) * s, dh = Double(img.height) * s
        ctx.saveGState()
        ctx.clip(to: CGRect(x: x, y: y, width: tw, height: th))
        ctx.draw(img, in: CGRect(x: Double(x) + (Double(tw) - dw) / 2, y: Double(y) + (Double(th) - dh) / 2, width: dw, height: dh))
        ctx.restoreGState()
    }
    let text = NSAttributedString(string: label.uppercased(), attributes: [
        .font: font, .foregroundColor: CGColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1)])
    let line = CTLineCreateWithAttributedString(text)
    ctx.textPosition = CGPoint(x: x + 10, y: y - bar + 10)
    CTLineDraw(line, ctx)
}

let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
guard CGImageDestinationFinalize(dest) else { print("could not write \(out.path)"); exit(1) }
print("wrote \(out.path) \(w)x\(h)")
