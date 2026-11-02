// soupcheck <photo.jpg> <stock.fs>
// Verifies SoupDesk's grading against the engine's own path:
//  A = engine JPEG decoder -> look, fed in camera-style strips (reference)
//  B = engine-decoded frame through SoupKit's Swift wrapper (must be identical)
//  C = ImageIO decode -> SoupKit (the app's real path; differs only by decoder rounding)
import Foundation
import SoupEngine
import SoupKit
import ImageIO
import CoreGraphics

let a = CommandLine.arguments
if a.count == 4 && a[1] == "--develop" {
    let st = try Stock(url: URL(fileURLWithPath: a[3]))
    let t = Date(); let out = try Photo.develop(URL(fileURLWithPath: a[2]), stock: st)
    print("wrote \(out.path) in \(String(format: "%.2f", Date().timeIntervalSince(t)))s"); exit(0)
}
if a.count == 4 && a[1] == "--preview" {
    let st = try Stock(url: URL(fileURLWithPath: a[3]))
    let img = try Photo.decode(URL(fileURLWithPath: a[2]), maxPixel: 1600)
    let g = try img.graded(with: st, scale: 2)
    var d = 0; var sat = 0
    for i in stride(from: 0, to: g.bytes.count, by: 3) { d += abs(Int(g.bytes[i]) - Int(img.bytes[i])); sat += abs(Int(g.bytes[i]) - Int(g.bytes[i+1])) }
    print("\(img.width)x\(img.height) meanR diff \(d / (g.bytes.count/3)) meanRG \(sat / (g.bytes.count/3))"); exit(0)
}
guard a.count == 3 else { print("usage: soupcheck photo.jpg stock.fs"); exit(2) }
let photo = URL(fileURLWithPath: a[1]), stock = try Stock(url: URL(fileURLWithPath: a[2]))
let data = try Data(contentsOf: photo)
var w: Int32 = 0, h: Int32 = 0
guard let p = data.withUnsafeBytes({ soup_engine_decode_jpeg($0.baseAddress, data.count, &w, &h) }) else { print("engine decode failed"); exit(1) }
let engineIn = RGBImage(width: Int(w), height: Int(h), bytes: Array(UnsafeBufferPointer(start: p, count: Int(w * h * 3))))
free(p)

var rw: Int32 = 0, rh: Int32 = 0
guard let rp = data.withUnsafeBytes({ soup_engine_reference(stock.ptr_for_check, $0.baseAddress, data.count, &rw, &rh) }) else { print("reference failed"); exit(1) }
let ref = Array(UnsafeBufferPointer(start: rp, count: Int(rw * rh * 3))); free(rp)
let viaKit = try engineIn.graded(with: stock, scale: 1)

func diff(_ x: [UInt8], _ y: [UInt8]) -> (max: Int, mean: Double, over2: Double) {
    var m = 0, s = 0, o = 0
    for i in 0..<min(x.count, y.count) { let d = abs(Int(x[i]) - Int(y[i])); m = max(m, d); s += d; if d > 2 { o += 1 } }
    return (m, Double(s) / Double(x.count), Double(o) / Double(x.count) * 100)
}
print("stock \(stock.name) on \(photo.lastPathComponent) \(w)x\(h)")
let ab = diff(ref, viaKit.bytes)
print(String(format: "A vs B (wrapper):        max %d  mean %.4f", ab.max, ab.mean))
let io = try Photo.decode(photo)
if CommandLine.arguments.count > 0 {
    import_diag()
}
func import_diag() {
    let src = CGImageSourceCreateWithURL(photo as CFURL, nil)!
    let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    print("ImageIO colorspace:", cg.colorSpace?.name as Any, "bpc", cg.bitsPerComponent, "bpp", cg.bitsPerPixel, "alpha", cg.alphaInfo.rawValue)
    let w = cg.width, h = cg.height
    var raw = [UInt8](repeating: 0, count: w * h * 4)
    raw.withUnsafeMutableBytes { b in
        let ctx = CGContext(data: b.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: cg.colorSpace!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h)) }
    var nb = [UInt8](); nb.reserveCapacity(w * h * 3)
    for i in 0..<(w * h) { nb.append(raw[i*4]); nb.append(raw[i*4+1]); nb.append(raw[i*4+2]) }
    let direct = RGBImage(width: w, height: h, bytes: nb)
    var s = [0, 0, 0]; var m = 0
    for i in 0..<direct.bytes.count { let d = Int(direct.bytes[i]) - Int(engineIn.bytes[i]); s[i % 3] += d; m = max(m, abs(d)) }
    let n = Double(direct.bytes.count / 3)
    print(String(format: "ImageIO (no colour conversion) vs engine: signed mean R %.3f G %.3f B %.3f  max %d", Double(s[0])/n, Double(s[1])/n, Double(s[2])/n, m))
}
if io.width == Int(w) && io.height == Int(h) {
    let dec = diff(engineIn.bytes, io.bytes)
    print(String(format: "decoders engine vs ImageIO: max %d  mean %.3f  >2: %.3f%%", dec.max, dec.mean, dec.over2))
    let ac = diff(ref, try io.graded(with: stock, scale: 1).bytes)
    print(String(format: "A vs C (app path):       max %d  mean %.3f  >2: %.3f%%", ac.max, ac.mean, ac.over2))
} else { print("ImageIO image is \(io.width)x\(io.height) (rotated?) - skipped C") }
exit(ab.max == 0 ? 0 : 1)
