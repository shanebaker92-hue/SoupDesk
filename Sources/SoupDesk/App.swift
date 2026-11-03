import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SoupKit

@main
struct SoupDeskApp: App {
    @StateObject private var model = Model()
    var body: some Scene {
        WindowGroup("SoupDesk") {
            // ideal, not .defaultSize: the first window opens at the ideal size, back to macOS 12
            ContentView().environmentObject(model)
                .frame(minWidth: 1100, idealWidth: 1240, minHeight: 680, idealHeight: 780)
        }
        .windowStyle(.hiddenTitleBar)       // no grey bar: the photo runs to the top edge
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.openPanel() }.keyboardShortcut("o")
            }
            CommandMenu("Film") {
                Button("Favourite This Stock") { model.toggleFavourite() }.keyboardShortcut("f", modifiers: [])
                Divider()
                Button("Import Stock Files…") { model.importPanel() }.keyboardShortcut("i")
                Button("Check for New Stocks") { model.fetchUpstream() }
                Button("Make Your Own Stock (Web Editor)") { model.openEditor() }
                Button("Show Stocks Folder") { model.showStocksFolder() }
            }
            CommandMenu("Develop") {
                Button("Develop This Photo") { model.developCurrent() }.keyboardShortcut("e")
                Button("Develop All Photos") { model.developAll() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

struct PhotoItem: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
}

@MainActor
final class Model: ObservableObject {
    nonisolated static let previewLong = 1600

    @Published var stocks: [Stock]
    /// Favourite stocks by NAME (stable whichever file they came from).
    @Published var favourites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "favourites") ?? [])
    @Published var photos: [PhotoItem] = []
    @Published var current: Int = 0 { didSet { refresh() } }
    /// Stock chosen per photo; -1 = original. New photos start on the last used stock.
    @Published var choice: [URL: Int] = [:]
    @Published var preview: CGImage?
    @Published var thumbs: [URL: CGImage] = [:]
    @Published var status = ""
    @Published var busy = false
    private var lastStock = 0

    private var proxies: [URL: (img: RGBImage, scale: Int)] = [:]
    private var graded: [String: CGImage] = [:]
    private var gradedOrder: [String] = []

    init() {
        stocks = Model.loadStocks()
        status = "\(stocks.count) film stocks. Drag photos or a folder in, or press CMD O."
        let args = CommandLine.arguments.dropFirst().filter { FileManager.default.fileExists(atPath: $0) }
        if !args.isEmpty { add(args.map { URL(fileURLWithPath: $0) }) }
    }

    var currentPhoto: PhotoItem? { photos.indices.contains(current) ? photos[current] : nil }
    var currentStock: Int {
        get { currentPhoto.flatMap { choice[$0.url] } ?? lastStock }
        set { if let p = currentPhoto { choice[p.url] = newValue }; if newValue >= 0 { lastStock = newValue }; refresh() }
    }

    func openPanel() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true; p.canChooseDirectories = true; p.canChooseFiles = true
        if p.runModal() == .OK { add(p.urls) }
    }

    func add(_ urls: [URL]) {
        let fs = urls.filter { $0.pathExtension.lowercased() == "fs" }
        if !fs.isEmpty { importStocks(fs) }
        let urls = urls.filter { $0.pathExtension.lowercased() != "fs" }
        if urls.isEmpty { return }
        var found: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                let items = (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []
                found += items.filter { Photo.extensions.contains($0.pathExtension.lowercased()) }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else if Photo.extensions.contains(u.pathExtension.lowercased()) {
                found.append(u)
            }
        }
        let known = Set(photos.map(\.url))
        let new = found.filter { !known.contains($0) }.map(PhotoItem.init)
        guard !new.isEmpty else { status = "No photos found there."; return }
        let first = photos.count
        photos += new
        current = first
        status = "\(photos.count) photos"
        for p in new { loadThumb(p.url) }
    }

    private func loadThumb(_ url: URL) {
        Task.detached(priority: .utility) {
            guard let img = try? Photo.decode(url, maxPixel: 160).cgImage() else { return }
            await MainActor.run { self.thumbs[url] = img }
        }
    }

    func move(photo d: Int) {
        guard !photos.isEmpty else { return }
        current = min(max(current + d, 0), photos.count - 1)
    }

    func move(stock d: Int) {
        let o = stockOrder
        let at = o.firstIndex(of: currentStock) ?? 0
        currentStock = o[min(max(at + d, 0), o.count - 1)]
    }

    /// Show the current photo with its stock; grade on a background task, cache results.
    func refresh() {
        guard let p = currentPhoto else { preview = nil; return }
        let url = p.url, s = currentStock
        let key = "\(url.path)#\(s)"
        if let c = graded[key] { preview = c; return }
        let stock = s >= 0 ? stocks[s] : nil
        let cachedProxy = proxies[url]
        busy = true
        Task.detached(priority: .userInitiated) {
            do {
                var px = cachedProxy
                if px == nil {
                    let img = try Photo.decode(url, maxPixel: Model.previewLong)
                    let full = Model.fullLongSide(url) ?? max(img.width, img.height)
                    px = (img, Photo.scale(fullLong: full, previewLong: max(img.width, img.height)))
                }
                let proxy = px!
                let out = try stock.map { try proxy.img.graded(with: $0, scale: proxy.scale) } ?? proxy.img
                let cg = out.cgImage()
                await MainActor.run {
                    self.proxies[url] = proxy
                    if self.proxies.count > 12, let k = self.proxies.keys.first(where: { $0 != url }) { self.proxies[k] = nil }
                    if let cg { self.cache(key, cg) }
                    if self.currentPhoto?.url == url && self.currentStock == s { self.preview = cg; self.busy = false }
                }
            } catch {
                await MainActor.run { self.status = error.localizedDescription; self.busy = false }
            }
        }
    }

    private func cache(_ key: String, _ img: CGImage) {
        graded[key] = img; gradedOrder.append(key)
        if gradedOrder.count > 60 { graded[gradedOrder.removeFirst()] = nil }
    }

    nonisolated static func fullLongSide(_ url: URL) -> Int? {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return max(w, h)
    }

    func developCurrent() {
        guard let p = currentPhoto else { return }
        develop([(p.url, currentStock)])
    }

    func developAll() {
        develop(photos.map { ($0.url, choice[$0.url] ?? lastStock) })
    }

    private func develop(_ jobs: [(URL, Int)]) {
        let jobs = jobs.filter { $0.1 >= 0 }.map { ($0.0, stocks[$0.1]) }
        guard !jobs.isEmpty, !busy else { status = "Pick a film stock first."; return }
        busy = true
        Task.detached(priority: .userInitiated) {
            var done = 0, last: URL?
            var failed: [String] = []
            for (url, stock) in jobs {
                let n = done + 1
                await MainActor.run { self.status = "Developing \(n) of \(jobs.count): \(url.lastPathComponent)..." }
                do { last = try Photo.develop(url, stock: stock); done += 1 }
                catch { failed.append(url.lastPathComponent) }
            }
            let msg = failed.isEmpty ? "Developed \(done) photo\(done == 1 ? "" : "s") into the Soup folder."
                                     : "Developed \(done); could not develop \(failed.joined(separator: ", "))."
            let shown = last
            await MainActor.run {
                self.status = msg; self.busy = false
                if let last = shown { NSWorkspace.shared.activateFileViewerSelecting([last]) }
            }
        }
    }
}

