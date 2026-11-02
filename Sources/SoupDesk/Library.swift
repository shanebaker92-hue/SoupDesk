import SwiftUI
import AppKit
import SoupKit

/// Film stock library: built-in stocks, the user's own, favourites, and fetching more.
extension Model {
    /// Where imported and downloaded stocks live. Never inside the app, so updates keep them.
    nonisolated static var userStocksDir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SoupDesk/Stocks", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Upstream Soup Engine's card folder: the source of new official stocks.
    nonisolated static let upstreamAPI = URL(string: "https://api.github.com/repos/jiijii0/soup-engine/contents/card/ML/FILM")!
    nonisolated static let editorURL = URL(string: "https://jiijii0.github.io/soup-stocks/")!

    /// Built-ins in camera order, then the user's stocks; the first stock with a given NAME wins.
    static func loadStocks() -> [Stock] {
        let builtin = Bundle.main.url(forResource: "Stocks", withExtension: nil)
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("Stocks")
        var out: [Stock] = [], names = Set<String>()
        for s in Stock.loadAll(from: builtin) + Stock.loadAll(from: userStocksDir) where names.insert(s.name).inserted {
            out.append(s)
        }
        return out
    }

    /// -1 (original), favourites, then the rest: the list order and the arrow-key order.
    var stockOrder: [Int] {
        let favs = stocks.indices.filter { favourites.contains(stocks[$0].name) }
        return [-1] + favs + stocks.indices.filter { !favourites.contains(stocks[$0].name) }
    }

    func isFavourite(_ i: Int) -> Bool { i >= 0 && favourites.contains(stocks[i].name) }

    func toggleFavourite(_ i: Int? = nil) {
        let i = i ?? currentStock
        guard i >= 0 else { return }
        let n = stocks[i].name
        if favourites.contains(n) { favourites.remove(n) } else { favourites.insert(n) }
        UserDefaults.standard.set(Array(favourites).sorted(), forKey: "favourites")
    }

    /// Validate .fs text and save it into the user folder. Returns the stock's NAME if it was new.
    @discardableResult
    func installStock(data: Data, suggestedName: String) -> String? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".fs")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard (try? data.write(to: tmp)) != nil, let s = try? Stock(url: tmp) else { return nil }
        guard !stocks.contains(where: { $0.name == s.name }) else { return nil }
        let base = suggestedName.lowercased().filter { $0.isLetter || $0.isNumber }
        var dest = Model.userStocksDir.appendingPathComponent((base.isEmpty ? "stock" : base) + ".fs")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = Model.userStocksDir.appendingPathComponent("\(base)\(n).fs"); n += 1
        }
        guard (try? data.write(to: dest)) != nil, let saved = try? Stock(url: dest) else { return nil }
        stocks.append(saved)       // appended, so photo choices (indices) stay valid
        return saved.name
    }

    func importStocks(_ urls: [URL]) {
        var added: [String] = [], skipped = 0
        for u in urls where u.pathExtension.lowercased() == "fs" {
            if let d = try? Data(contentsOf: u), let n = installStock(data: d, suggestedName: u.deletingPathExtension().lastPathComponent) {
                added.append(n)
            } else { skipped += 1 }
        }
        status = added.isEmpty ? "No new stocks (\(skipped) already here or not a valid .fs)."
                               : "Added \(added.joined(separator: ", "))" + (skipped > 0 ? ". Skipped \(skipped)." : ".")
        if let n = added.first, let i = stocks.firstIndex(where: { $0.name == n }) { currentStock = i }
    }

    func importPanel() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.allowedContentTypes = [.init(filenameExtension: "fs") ?? .data]
        p.message = "Choose .fs film stock files"
        if p.runModal() == .OK { importStocks(p.urls) }
    }

    /// Download any upstream stock whose NAME isn't here yet.
    func fetchUpstream() {
        status = "Checking for new stocks..."
        busy = true
        Task {
            defer { busy = false }
            struct Item: Decodable { let name: String; let download_url: String? }
            do {
                var req = URLRequest(url: Model.upstreamAPI)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (d, _) = try await URLSession.shared.data(for: req)
                let items = try JSONDecoder().decode([Item].self, from: d).filter { $0.name.lowercased().hasSuffix(".fs") }
                var added: [String] = []
                for it in items {
                    guard let s = it.download_url, let u = URL(string: s),
                          let (fd, _) = try? await URLSession.shared.data(from: u) else { continue }
                    if let n = installStock(data: fd, suggestedName: (it.name as NSString).deletingPathExtension) { added.append(n) }
                }
                status = added.isEmpty ? "You have every stock (\(items.count) checked)."
                                       : "New: \(added.joined(separator: ", "))"
            } catch {
                status = "Could not reach the stock library. Check your internet connection."
            }
        }
    }

    func openEditor() { NSWorkspace.shared.open(Model.editorURL) }
    func showStocksFolder() { NSWorkspace.shared.open(Model.userStocksDir) }
}
