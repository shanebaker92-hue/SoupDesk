import SwiftUI
import CoreGraphics

// MARK: - Palette (the 7D UI's dark greys plus one warm accent)

enum Pix {
    static let bg      = Color(hex: 0x0d0d0d)
    static let panel   = Color(hex: 0x1a1a1a)
    static let line    = Color(hex: 0x3a3a3a)
    static let dim     = Color(hex: 0x7a7a7a)
    static let text    = Color(hex: 0xe6e6e6)
    static let accent  = Color(hex: 0xf5b021)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

// MARK: - Bitmap text in the 7D's 5x7 font

/// Uppercase-only, like the camera. `px` is the size of one font pixel in points.
struct PixelText: View {
    let text: String
    var px: CGFloat = 2
    var color: Color = Pix.text

    private var chars: [Character] { Array(text.uppercased()) }

    var body: some View {
        let w = CGFloat(max(chars.count * 6 - 1, 0)) * px
        Canvas { ctx, _ in
            var x: CGFloat = 0
            for c in chars {
                let g = PixelText.glyph(c)
                for col in 0..<5 {
                    let bits = g[col]
                    for row in 0..<7 where bits >> row & 1 == 1 {
                        ctx.fill(Path(CGRect(x: x + CGFloat(col) * px, y: CGFloat(row) * px, width: px, height: px)), with: .color(color))
                    }
                }
                x += 6 * px
            }
        }
        .frame(width: w, height: 7 * px)
    }

    static func glyph(_ c: Character) -> [UInt8] {
        guard let v = c.asciiValue, v >= 0x20, v < 0x60 else { return PixelFont.glyphs[0] }
        return PixelFont.glyphs[Int(v) - 0x20]
    }
}

/// Wraps pixel text onto lines that fit `maxChars`.
struct PixelParagraph: View {
    let text: String
    var maxChars = 26
    var px: CGFloat = 1
    var color: Color = Pix.dim

    var body: some View {
        VStack(alignment: .leading, spacing: px * 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in PixelText(text: l, px: px, color: color) }
        }
    }

    private var lines: [String] {
        var out: [String] = [], cur = ""
        for w in text.split(separator: " ") {
            if cur.isEmpty { cur = String(w) }
            else if cur.count + 1 + w.count <= maxChars { cur += " " + w }
            else { out.append(cur); cur = String(w) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}

// MARK: - Pixel-art film, one per stock

/// Colours and label for the roll a stock is based on. Colour schemes only:
/// no logos or trade dress beyond "yellow box, red band".
struct FilmLook {
    enum Shape { case canister, cineCan }
    var shape: Shape = .canister
    var body: UInt32
    var band: UInt32
    var label: UInt32
    var iso: String
    var maker: String   // shown as text under the stock name

    static func forStock(_ id: String, name: String = "") -> FilmLook {
        switch id {
        case "portra":   return .init(body: 0xf2e6d0, band: 0xe8a33c, label: 0x3a2a1a, iso: "400", maker: "Kodak Portra 400")
        case "portr160": return .init(body: 0xf2e6d0, band: 0xd98a3a, label: 0x3a2a1a, iso: "160", maker: "Kodak Portra 160")
        case "portr800": return .init(body: 0xf2e6d0, band: 0xc0392b, label: 0x3a2a1a, iso: "800", maker: "Kodak Portra 800")
        case "ektar":    return .init(body: 0xe8b021, band: 0xd2402a, label: 0x1a1a1a, iso: "100", maker: "Kodak Ektar 100")
        case "gold":     return .init(body: 0xf5c518, band: 0xd24a1a, label: 0x1a1a1a, iso: "200", maker: "Kodak Gold 200")
        case "ultramax": return .init(body: 0xf5c518, band: 0x2a5db0, label: 0x1a1a1a, iso: "400", maker: "Kodak UltraMax 400")
        case "ektachr":  return .init(body: 0xeeeeee, band: 0xf5c518, label: 0xc62828, iso: "E1", maker: "Kodak Ektachrome E100")
        case "kodachr":  return .init(body: 0xf5c518, band: 0xc62828, label: 0x1a1a1a, iso: "K64", maker: "Kodachrome 64")
        case "trix":     return .init(body: 0xf5c518, band: 0x1a1a1a, label: 0x1a1a1a, iso: "400", maker: "Kodak Tri-X 400")
        case "tmax":     return .init(body: 0xeeeeee, band: 0xf5c518, label: 0x1a1a1a, iso: "TMY", maker: "Kodak T-Max 400")
        case "vis250d":  return .init(shape: .cineCan, body: 0x9a9a9a, band: 0xf5c518, label: 0x1a1a1a, iso: "250D", maker: "Kodak Vision3 250D")
        case "vis500t":  return .init(shape: .cineCan, body: 0x9a9a9a, band: 0x2a5db0, label: 0xeeeeee, iso: "500T", maker: "Kodak Vision3 500T")
        case "velvia":   return .init(body: 0x1f7a3a, band: 0xe23b2e, label: 0xeeeeee, iso: "50", maker: "Fujichrome Velvia 50")
        case "provia":   return .init(body: 0x2f3f9a, band: 0xeeeeee, label: 0xeeeeee, iso: "100", maker: "Fujichrome Provia 100F")
        case "astia":    return .init(body: 0x7a4fb0, band: 0xeeeeee, label: 0xeeeeee, iso: "100", maker: "Fujichrome Astia 100F")
        case "acros":    return .init(body: 0x1a1a1a, band: 0x8a8a8a, label: 0xeeeeee, iso: "100", maker: "Fujifilm Acros 100")
        case "clchrome": return .init(body: 0xb8b2a4, band: 0x5a5a4a, label: 0x1a1a1a, iso: "CC", maker: "Fujifilm Classic Chrome")
        case "clneg":    return .init(body: 0x2e8b57, band: 0xc0392b, label: 0xeeeeee, iso: "NEG", maker: "Fujifilm Classic Neg")
        case "nostneg":  return .init(body: 0xc98a4b, band: 0x6b3a1a, label: 0xf5e6c8, iso: "NN", maker: "Fujifilm Nostalgic Neg")
        case "realaace": return .init(body: 0xe8e8e8, band: 0x1f7a3a, label: 0x1a1a1a, iso: "ACE", maker: "Fujifilm Reala Ace")
        case "superia":  return .init(body: 0x1f7a3a, band: 0xeeeeee, label: 0xeeeeee, iso: "400", maker: "Fujifilm Superia 400")
        case "pro400h":  return .init(body: 0x4a8fb0, band: 0xeeeeee, label: 0xeeeeee, iso: "400", maker: "Fujifilm Pro 400H")
        case "eterna":   return .init(shape: .cineCan, body: 0x8a8a8a, band: 0x2e8b57, label: 0xeeeeee, iso: "ETR", maker: "Fujifilm Eterna")
        case "bleach":   return .init(shape: .cineCan, body: 0x6a6a6a, band: 0xc8c8c8, label: 0x1a1a1a, iso: "BB", maker: "Eterna, bleach bypass")
        case "hp5":      return .init(body: 0xeeeeee, band: 0x1a1a1a, label: 0x1a1a1a, iso: "HP5", maker: "Ilford HP5 Plus 400")
        case "delta32":  return .init(body: 0xeeeeee, band: 0x2a2a2a, label: 0xc62828, iso: "3K2", maker: "Ilford Delta 3200")
        case "soup800":  return .init(body: 0x1a1a1a, band: 0xd83a2a, label: 0xff8a3a, iso: "800", maker: "Soup original (halation)")
        default:
            // An imported stock: grey roll, ISO from its name if it has one, else its initials.
            let digits = name.split(separator: " ").first { $0.allSatisfy(\.isNumber) }
            let tag = digits.map { String($0.prefix(3)) } ?? String(name.filter { $0.isLetter }.prefix(3))
            return .init(body: 0x6a6a7a, band: 0xf5b021, label: 0xeeeeee, iso: tag.isEmpty ? "?" : tag, maker: "Your stock")
        }
    }
}

/// 28x32 sprite. Built once per stock into a CGImage and scaled with no smoothing.
enum FilmSprite {
    static let w = 28, h = 32
    private static var cache: [String: CGImage] = [:]
    static let original: CGImage = render(nil)

    static func image(for id: String, name: String = "") -> CGImage {
        let key = id + "|" + name
        if let c = cache[key] { return c }
        let img = render(FilmLook.forStock(id, name: name))
        cache[key] = img
        return img
    }

    private static func render(_ f: FilmLook?) -> CGImage {
        var px = [UInt32](repeating: 0, count: w * h)    // 0 = transparent, else 0xRRGGBB | 1<<24
        func set(_ x: Int, _ y: Int, _ c: UInt32) { if x >= 0, x < w, y >= 0, y < h { px[y * w + x] = c | 0x1000000 } }
        func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: UInt32) { for y in y0...y1 { for x in x0...x1 { set(x, y, c) } } }
        func shade(_ c: UInt32, _ k: Double) -> UInt32 {
            let r = min(255, Double(c >> 16 & 0xff) * k), g = min(255, Double(c >> 8 & 0xff) * k), b = min(255, Double(c & 0xff) * k)
            return UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
        }
        func text(_ s: String, cx: Int, y: Int, _ c: UInt32) {
            let chars = Array(s.uppercased()); var x = cx - (chars.count * 6 - 1) / 2
            for ch in chars {
                let g = PixelText.glyph(ch)
                for col in 0..<5 { for row in 0..<7 where g[col] >> row & 1 == 1 { set(x + col, y + row, c) } }
                x += 6
            }
        }

        if let f, f.shape == .canister {
            // film leader, with sprocket holes
            rect(22, 9, 27, 24, 0x5a3a1a)
            for y in stride(from: 10, through: 23, by: 3) { set(26, y, 0x2a1a0a) }
            rect(22, 9, 22, 24, 0x3a2410)
            // caps and spool
            rect(9, 0, 15, 2, 0x8a8a8a); rect(10, 0, 11, 1, 0xc8c8c8)
            rect(3, 3, 21, 5, 0x3a3a3a); rect(3, 27, 21, 29, 0x3a3a3a)
            rect(4, 3, 20, 3, 0x5a5a5a); rect(4, 29, 20, 29, 0x222222)
            // body
            rect(2, 6, 22, 26, f.body)
            rect(2, 6, 2, 26, shade(f.body, 0.6)); rect(22, 6, 22, 26, shade(f.body, 0.6))
            rect(4, 6, 4, 26, shade(f.body, 1.25))
            rect(2, 8, 22, 12, f.band)
            rect(4, 8, 4, 12, shade(f.band, 1.25))
            text(f.iso, cx: 12, y: 16, f.label)
            rect(2, 24, 22, 24, shade(f.band, 0.85))
        } else if let f {
            // round cine can, seen from above
            let cx = 13.5, cy = 15.5
            for y in 0..<h { for x in 0..<w {
                let d = ((Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy)).squareRoot()
                if d <= 13.5 { set(x, y, d > 12.5 ? shade(f.body, 0.55) : d > 11 ? shade(f.body, 1.2) : f.body) }
                if d <= 3 { set(x, y, shade(f.body, 0.7)) }
            } }
            rect(2, 19, 25, 26, f.band)
            rect(3, 19, 24, 19, shade(f.band, 1.2))
            text(f.iso, cx: 13, y: 20, f.label)
            for (x, y) in [(6, 6), (21, 6), (6, 14), (21, 14)] { set(x, y, shade(f.body, 0.6)) }
        } else {
            // "Original": an empty slide mount
            rect(3, 4, 24, 27, 0xe6e6e6)
            rect(8, 9, 19, 22, 0x0d0d0d)
            rect(3, 27, 24, 27, 0x9a9a9a); rect(24, 4, 24, 27, 0x9a9a9a)
        }

        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) where px[i] != 0 {
            bytes[i * 4] = UInt8(px[i] >> 16 & 0xff); bytes[i * 4 + 1] = UInt8(px[i] >> 8 & 0xff)
            bytes[i * 4 + 2] = UInt8(px[i] & 0xff); bytes[i * 4 + 3] = 255
        }
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}

struct FilmSpriteView: View {
    let id: String?          // nil = original
    var name: String? = nil
    var scale: CGFloat = 2
    var body: some View {
        Image(decorative: id.map { FilmSprite.image(for: $0, name: name ?? "") } ?? FilmSprite.original, scale: 1)
            .resizable().interpolation(.none)
            .frame(width: CGFloat(FilmSprite.w) * scale, height: CGFloat(FilmSprite.h) * scale)
    }
}

// MARK: - Pixel button: 1px-style border, inverts when hovered

struct PixelButton: View {
    let title: String
    var key: String? = nil
    var px: CGFloat = 2
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                PixelText(text: title, px: px, color: hover && enabled ? Pix.bg : enabled ? Pix.text : Pix.line)
                if let key { PixelText(text: key, px: 1, color: hover && enabled ? Pix.bg : Pix.dim) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(hover && enabled ? Pix.accent : Pix.panel)
            .overlay(Rectangle().strokeBorder(enabled ? Pix.accent : Pix.line, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .onHover { hover = $0 }
    }
}

// MARK: - Pixel star (favourite)

struct StarView: View {
    let on: Bool
    var dark = false
    var px: CGFloat = 2
    private static let rows = ["...#...", "...#...", "..###..", "#######", ".#####.", "..###..", ".##.##.", "##...##"]

    var body: some View {
        let fill = dark ? Pix.bg : on ? Pix.accent : Pix.line
        Canvas { ctx, _ in
            for (y, r) in StarView.rows.enumerated() {
                for (x, c) in r.enumerated() where c == "#" {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)), with: .color(fill))
                }
            }
        }
        .frame(width: 7 * px, height: 8 * px)
        .opacity(on ? 1 : dark ? 0.35 : 0.8)
        .padding(4)
        .contentShape(Rectangle())
    }
}
