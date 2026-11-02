import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SoupKit

@main
struct SoupDeskApp: App {
    @StateObject private var model = Model()
    var body: some Scene {
        WindowGroup("SoupDesk") {
            ContentView().environmentObject(model).frame(minWidth: 1100, minHeight: 680)
        }
        .defaultSize(width: 1240, height: 780)
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

struct ContentView: View {
    @EnvironmentObject var m: Model
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            photoStrip.frame(width: 150).background(Pix.panel)
            Rectangle().fill(Pix.line).frame(width: 2)
            VStack(spacing: 0) {
                header
                Rectangle().fill(Pix.line).frame(height: 2)
                ZStack {
                    Pix.bg
                    if let img = m.preview {
                        Image(decorative: img, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(16)
                    } else {
                        VStack(spacing: 16) {
                            FilmSpriteView(id: "portra", scale: 4)
                            PixelText(text: "Drop photos or a folder here", px: 3, color: Pix.dim)
                        }
                    }
                }
                Rectangle().fill(Pix.line).frame(height: 2)
                footer
            }
            Rectangle().fill(Pix.line).frame(width: 2)
            stockList.frame(width: 300).background(Pix.panel)
        }
        .background(Pix.bg)
        .preferredColorScheme(.dark)
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { m.move(photo: -1); return .handled }
        .onKeyPress(.rightArrow) { m.move(photo: 1); return .handled }
        .onKeyPress(.upArrow) { m.move(stock: -1); return .handled }
        .onKeyPress(.downArrow) { m.move(stock: 1); return .handled }
        .onKeyPress(.return) { m.developCurrent(); return .handled }
        .onKeyPress("f") { m.toggleFavourite(); return .handled }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                var urls: [URL] = []
                for p in providers {
                    if let u = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                       let url = URL(dataRepresentation: u, relativeTo: nil) { urls.append(url) }
                }
                await MainActor.run { m.add(urls) }
            }
            return true
        }
    }

    /// The current stock, large, with what it's based on.
    var header: some View {
        let s = m.currentStock >= 0 ? m.stocks[m.currentStock] : nil
        return HStack(alignment: .center, spacing: 16) {
            FilmSpriteView(id: s?.id, name: s?.name, scale: 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    PixelText(text: s?.name ?? "Original", px: 4, color: Pix.accent)
                    if m.currentStock >= 0 {
                        StarView(on: m.isFavourite(m.currentStock), dark: false, px: 3)
                            .onTapGesture { m.toggleFavourite(); focused = true }
                    }
                }
                PixelText(text: s.map { FilmLook.forStock($0.id, name: $0.name).maker } ?? "No film look", px: 2)
                PixelText(text: s?.desc ?? "Your photo as it came out of the camera", px: 1, color: Pix.dim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                PixelText(text: "Up/Down  film", px: 1, color: Pix.dim)
                PixelText(text: "Left/Right  photo", px: 1, color: Pix.dim)
                PixelText(text: "F  favourite", px: 1, color: Pix.dim)
                PixelText(text: "Return  develop", px: 1, color: Pix.dim)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Pix.panel)
    }

    var footer: some View {
        HStack(spacing: 10) {
            PixelText(text: m.busy ? m.status + " *" : m.status, px: 1, color: Pix.dim)
            Spacer()
            PixelButton(title: "Develop", key: "CMD E") { m.developCurrent() }.disabled(m.currentPhoto == nil || m.busy)
            PixelButton(title: "Develop all", key: "SHIFT CMD E") { m.developAll() }.disabled(m.photos.isEmpty || m.busy)
        }
        .padding(10).background(Pix.panel)
    }

    var photoStrip: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(m.photos.enumerated()), id: \.element.id) { i, p in
                        VStack(spacing: 4) {
                            Group {
                                if let t = m.thumbs[p.url] { Image(decorative: t, scale: 1).resizable().aspectRatio(contentMode: .fit) }
                                else { Pix.line.aspectRatio(1.5, contentMode: .fit) }
                            }.frame(height: 80)
                            PixelText(text: String(p.url.lastPathComponent.prefix(20)), px: 1, color: i == m.current ? Pix.accent : Pix.dim)
                        }
                        .padding(5)
                        .overlay(Rectangle().strokeBorder(i == m.current ? Pix.accent : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                        .onTapGesture { m.current = i; focused = true }
                        .id(i)
                    }
                }.padding(8)
            }
            .onChange(of: m.current) { _, i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
        }
    }

    var stockList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                PixelButton(title: "Get stocks", px: 1.5) { m.fetchUpstream() }.disabled(m.busy)
                PixelButton(title: "Import", px: 1.5) { m.importPanel() }
                PixelButton(title: "Make", px: 1.5) { m.openEditor() }
            }
            .padding(8)
            Rectangle().fill(Pix.line).frame(height: 2)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        let order = m.stockOrder
                        let favCount = order.filter { m.isFavourite($0) }.count
                        ForEach(Array(order.enumerated()), id: \.element) { pos, i in
                            if pos == 1 && favCount > 0 { sectionLabel("Favourites") }
                            if pos == 1 + favCount && pos < order.count { sectionLabel(favCount > 0 ? "All film" : "Film") }
                            if i < 0 { row(-1, nil, "Original", "No film look") }
                            else { row(i, m.stocks[i].id, m.stocks[i].name, FilmLook.forStock(m.stocks[i].id, name: m.stocks[i].name).maker) }
                        }
                    }.padding(6)
                }
                .onChange(of: m.currentStock) { _, i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
            }
        }
    }

    func sectionLabel(_ t: String) -> some View {
        PixelText(text: t, px: 1, color: Pix.accent).padding(.top, 8).padding(.bottom, 2).padding(.leading, 6)
    }

    func row(_ i: Int, _ id: String?, _ title: String, _ sub: String) -> some View {
        let on = i == m.currentStock
        return HStack(spacing: 10) {
            FilmSpriteView(id: id, name: i >= 0 ? title : nil, scale: 1.5)
            VStack(alignment: .leading, spacing: 5) {
                PixelText(text: title, px: 2, color: on ? Pix.bg : Pix.text)
                PixelText(text: sub, px: 1, color: on ? Pix.bg : Pix.dim)
            }
            Spacer(minLength: 0)
            if i >= 0 {
                StarView(on: m.isFavourite(i), dark: on)
                    .onTapGesture { m.toggleFavourite(i); focused = true }
                    .accessibilityLabel(m.isFavourite(i) ? "Remove favourite" : "Add favourite")
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(on ? Pix.accent : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { m.currentStock = i; focused = true }
        .id(i)
    }
}
