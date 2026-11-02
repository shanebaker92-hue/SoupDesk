import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import SoupEngine

public enum SoupError: Error, LocalizedError {
    case badStock(String), decode(URL), grade, encode(URL)
    public var errorDescription: String? {
        switch self {
        case .badStock(let f): return "Couldn't read film stock \(f)"
        case .decode(let u): return "Couldn't open \(u.lastPathComponent)"
        case .grade: return "Grading failed"
        case .encode(let u): return "Couldn't write \(u.lastPathComponent)"
        }
    }
}

/// One parsed .fs film stock.
public final class Stock: Identifiable, @unchecked Sendable {
    public let id: String          // file base name, e.g. "portra"
    public let name: String        // NAME line, e.g. "PORTRA"
    public let desc: String
    let ptr: OpaquePointer
    public var ptr_for_check: OpaquePointer { ptr }

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let p = data.withUnsafeBytes({ soup_stock_load($0.baseAddress, data.count) })
        else { throw SoupError.badStock(url.lastPathComponent) }
        ptr = p
        id = url.deletingPathExtension().lastPathComponent
        name = String(cString: soup_stock_name(p))
        desc = String(cString: soup_stock_desc(p))
    }
    deinit { soup_stock_free(ptr) }

    /// Stocks in INDEX.TXT order (the camera's order); any extras after.
    public static func loadAll(from dir: URL) -> [Stock] {
        let fm = FileManager.default
        var order: [String] = []
        if let idx = try? String(contentsOf: dir.appendingPathComponent("INDEX.TXT"), encoding: .utf8) {
            order = idx.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasSuffix(".fs") }
        }
        let all = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".fs") }.sorted()
        for f in all where !order.contains(f) { order.append(f) }
        return order.compactMap { try? Stock(url: dir.appendingPathComponent($0)) }
    }
}

/// Packed 8-bit sRGB, 3 bytes per pixel.
public struct RGBImage: @unchecked Sendable {
    public let width: Int, height: Int
    public var bytes: [UInt8]

    public init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width; self.height = height; self.bytes = bytes
    }

    public func cgImage() -> CGImage? {
        guard let prov = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                       bytesPerRow: width * 3, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Draw any CGImage into sRGB and drop alpha.
    public init?(cgImage img: CGImage) {
        let w = img.width, h = img.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let ok = rgba.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        rgb.withUnsafeMutableBufferPointer { o in
            rgba.withUnsafeBufferPointer { i in
                for p in 0..<(w * h) {
                    o[p * 3] = i[p * 4]; o[p * 3 + 1] = i[p * 4 + 1]; o[p * 3 + 2] = i[p * 4 + 2]
                }
            }
        }
        self.init(width: w, height: h, bytes: rgb)
    }

    /// Run the Soup Engine look. `scale` is the camera's decode scale (1/2/4).
    public func graded(with stock: Stock, scale: Int) throws -> RGBImage {
        var out = [UInt8](repeating: 0, count: bytes.count)
        let rc = bytes.withUnsafeBufferPointer { i in
            out.withUnsafeMutableBufferPointer { o in
                soup_grade(stock.ptr, Int32(scale), i.baseAddress, Int32(width), Int32(height), width * 3, o.baseAddress)
            }
        }
        if rc != 0 { throw SoupError.grade }
        return RGBImage(width: width, height: height, bytes: out)
    }
}

public enum Photo {
    public static let extensions: Set<String> = ["jpg", "jpeg", "nrw", "nef", "cr2", "cr3", "dng", "arw", "raf", "orf", "rw2", "pef", "srw", "tif", "tiff", "heic"]

    public static func isRaw(_ url: URL) -> Bool {
        guard let t = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return t.conforms(to: .rawImage)
    }

    static let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])

    /// Decode with orientation applied. `maxPixel` nil = full resolution.
    public static func decode(_ url: URL, maxPixel: Int? = nil) throws -> RGBImage {
        if isRaw(url), let f = CIRAWFilter(imageURL: url) {
            let full = f.nativeSize
            if let m = maxPixel {
                let long = max(full.width, full.height)
                if long > CGFloat(m) { f.scaleFactor = Float(CGFloat(m) / long) }
            }
            guard let img = f.outputImage,
                  let cg = ci.createCGImage(img, from: img.extent, format: .RGBA8,
                                            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!),
                  let rgb = RGBImage(cgImage: cg) else { throw SoupError.decode(url) }
            return rgb
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { throw SoupError.decode(url) }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixel ?? Int.max, max(w, h)),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
              let rgb = RGBImage(cgImage: cg) else { throw SoupError.decode(url) }
        return rgb
    }

    /// Camera-style scale for a preview of `previewLong` px from a `fullLong` px original,
    /// so grain and halation look in the preview as they will in the export.
    public static func scale(fullLong: Int, previewLong: Int) -> Int {
        let r = Double(fullLong) / Double(max(previewLong, 1))
        return r >= 3 ? 4 : r >= 1.5 ? 2 : 1
    }

    /// <folder>/Soup/<name>_<stock>.jpg, never an existing file.
    public static func outputURL(for src: URL, stock: Stock) -> URL {
        let dir = src.deletingLastPathComponent().appendingPathComponent("Soup", isDirectory: true)
        let base = src.deletingPathExtension().lastPathComponent + "_" + stock.id
        var url = dir.appendingPathComponent(base + ".jpg")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base)-\(n).jpg"); n += 1
        }
        return url
    }

    /// Full-resolution develop. Returns the file written.
    @discardableResult
    public static func develop(_ src: URL, stock: Stock, quality: Double = 0.92) throws -> URL {
        let img = try decode(src)
        let graded = try img.graded(with: stock, scale: 1)
        let out = outputURL(for: src, stock: stock)
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let cg = graded.cgImage(),
              let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw SoupError.encode(out) }
        var meta: [CFString: Any] = [:]
        if let s = CGImageSourceCreateWithURL(src as CFURL, nil),
           let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] {
            for k in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary] { if let v = p[k] { meta[k] = v } }
            var tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFSoftware] = "SoupDesk - \(stock.name)"
            tiff[kCGImagePropertyTIFFOrientation] = 1
            meta[kCGImagePropertyTIFFDictionary] = tiff
        }
        meta[kCGImagePropertyOrientation] = 1          // pixels are already upright
        meta[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(dest, cg, meta as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw SoupError.encode(out) }
        return out
    }
}
