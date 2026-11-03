import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SoupKit

/// The photo, edge to edge, with glass chrome floating over it: filmstrip left, stocks right,
/// toolbar on top and the 7D's speed band and position ticks underneath.
struct ContentView: View {
    @EnvironmentObject var m: Model
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            ambient
            HStack(spacing: 10) {
                photoStrip.frame(width: 160).glass(in: Panel.shape)
                    .padding(.top, 26)          // the traffic lights sit above it, on the backdrop
                VStack(spacing: 12) {
                    toolbar
                    stage.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 6)
                    hud
                }
                .padding(.vertical, 2)
                stockPanel.frame(width: 306).glass(in: Panel.shape)
            }
            .padding(10)
        }
        .ignoresSafeArea()
        .background(WindowChrome())
        .preferredColorScheme(.dark)
        .keyControls(focused: $focused, m)
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

    /// The current photo blurred and dimmed behind everything, so the glass has colour to bend.
    var ambient: some View {
        Color.clear.overlay {
            if let img = m.preview {
                Image(decorative: img, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    .scaleEffect(1.25).blur(radius: 70).brightness(-0.3).saturation(1.35)
            }
        }
        .background(Pix.bg)
        .clipped()
    }

    var stage: some View {
        Group {
            if let img = m.preview {
                Image(decorative: img, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 25, y: 18)
            } else {
                VStack(spacing: 16) {
                    FilmSpriteView(id: "portra", scale: 4)
                    PixelText(text: "Drop photos or a folder here", px: 3, color: Pix.dim)
                }
            }
        }
    }

    var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                stepButton("<", "Previous photo") { m.move(photo: -1) }
                PixelText(text: m.photos.isEmpty ? "No photos" : "\(m.current + 1) of \(m.photos.count)", px: 1, color: Pix.dim)
                stepButton(">", "Next photo") { m.move(photo: 1) }
                if let p = m.currentPhoto {
                    Rectangle().fill(Pix.text.opacity(0.18)).frame(width: 1, height: 18).padding(.horizontal, 6)
                    PixelText(text: String(p.url.lastPathComponent.prefix(24)), px: 2).padding(.trailing, 10)
                }
            }
            .padding(.horizontal, 6).frame(height: 38)
            .glass(in: Capsule())
            Spacer(minLength: 0)
            GlassButton(title: "Develop all") { m.developAll() }
                .disabled(m.photos.isEmpty || m.busy).help("Develop all photos (Shift Cmd E)")
            GlassButton(title: "Develop", primary: true) { m.developCurrent() }
                .disabled(m.currentPhoto == nil || m.busy).help("Develop this photo (Cmd E)")
        }
    }

    func stepButton(_ glyph: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: { action(); focused = true }) {
            PixelText(text: glyph, px: 2).frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(m.photos.count < 2)
    }

    /// Name, speed band, favourite star; ticks for where you are in the stocks; status underneath.
    var hud: some View {
        let s = m.currentStock >= 0 ? m.stocks[m.currentStock] : nil
        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                PixelText(text: s?.name ?? "Original", px: 3)
                SpeedBand(look: s.map { FilmLook.forStock($0.id, name: $0.name) })
                if s != nil {
                    StarView(on: m.isFavourite(m.currentStock), px: 2)
                        .onTapGesture { m.toggleFavourite(); focused = true }
                        .accessibilityLabel(m.isFavourite(m.currentStock) ? "Remove favourite" : "Add favourite")
                }
            }
            ticks
            PixelText(text: m.busy ? m.status + " *" : m.status, px: 1, color: Pix.dim)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// One tick per stock in list order, as on the camera: current tall and light, favourites amber.
    var ticks: some View {
        let n = m.stocks.count, narrow = n > 40
        return HStack(alignment: .bottom, spacing: narrow ? 2 : 4) {
            ForEach(0..<n, id: \.self) { i in
                let here = i == m.currentStock, fav = m.isFavourite(i)
                RoundedRectangle(cornerRadius: 2)
                    .fill(here ? Pix.text : fav ? Pix.accent : Pix.text.opacity(0.28))
                    .frame(width: (narrow ? 4 : 8) + (here ? 2 : 0), height: here ? 6 : fav ? 4 : 3)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    var photoStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            PixelText(text: m.photos.isEmpty ? "No photos yet" : "\(m.photos.count) photos", px: 1, color: Pix.dim)
                .padding(.leading, 2)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(m.photos.enumerated()), id: \.element.id) { i, p in
                            let on = i == m.current
                            VStack(alignment: .leading, spacing: 5) {
                                Group {
                                    if let t = m.thumbs[p.url] { Image(decorative: t, scale: 1).resizable().aspectRatio(contentMode: .fill) }
                                    else { Pix.line.opacity(0.4) }
                                }
                                .frame(width: 132, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(2)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(on ? Pix.accent : Pix.text.opacity(0.12), lineWidth: on ? 2 : 1))
                                PixelText(text: String(p.url.lastPathComponent.prefix(20)), px: 1, color: on ? Pix.accent : Pix.dim)
                                    .padding(.leading, 2)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { m.current = i; focused = true }
                            .id(i)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .onChange(of: m.current) { i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
            }
        }
        .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 12)
    }

    var stockPanel: some View {
        let s = m.currentStock >= 0 ? m.stocks[m.currentStock] : nil
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                WellButton(title: "Get stocks") { m.fetchUpstream() }.disabled(m.busy)
                WellButton(title: "Import") { m.importPanel() }
                WellButton(title: "Make") { m.openEditor() }
            }
            .padding(3).well(17)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        let order = m.stockOrder
                        let favCount = order.filter { m.isFavourite($0) }.count
                        ForEach(Array(order.enumerated()), id: \.element) { pos, i in
                            if pos == 1 && favCount > 0 { sectionLabel("Favourites") }
                            if pos == 1 + favCount && pos < order.count { sectionLabel(favCount > 0 ? "All film" : "Film") }
                            StockRow(index: i, focused: $focused).id(i)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: m.currentStock) { i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
            }
            VStack(alignment: .leading, spacing: 8) {
                PixelText(text: s.map { FilmLook.forStock($0.id, name: $0.name).maker } ?? "No film look", px: 1, color: Pix.accent)
                PixelParagraph(text: s?.desc ?? "Your photo as it came out of the camera", maxChars: 40, px: 1, color: Pix.text.opacity(0.8))
                PixelText(text: "Up/Down film  Left/Right photo  F fav", px: 1, color: Pix.dim).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).well()
        }
        .padding(12)
    }

    func sectionLabel(_ t: String) -> some View {
        PixelText(text: t, px: 1, color: Pix.accent).padding(.top, 10).padding(.bottom, 2).padding(.leading, 10)
    }
}

extension View {
    /// Arrows change photo and film, Return develops (F is the Film menu's shortcut). SwiftUI's key
    /// handlers on macOS 14+; a key monitor on the window before that.
    @ViewBuilder
    func keyControls(focused: FocusState<Bool>.Binding, _ m: Model) -> some View {
        if #available(macOS 14, *) {
            focusable().focused(focused).focusEffectDisabled()
                .onAppear { focused.wrappedValue = true }
                .onKeyPress(.leftArrow) { m.move(photo: -1); return .handled }
                .onKeyPress(.rightArrow) { m.move(photo: 1); return .handled }
                .onKeyPress(.upArrow) { m.move(stock: -1); return .handled }
                .onKeyPress(.downArrow) { m.move(stock: 1); return .handled }
                .onKeyPress(.return) { m.developCurrent(); return .handled }
                .onKeyPress("f") { m.toggleFavourite(); return .handled }
        } else {
            background(KeyMonitor(m: m))
        }
    }
}

/// The macOS 12–13 keys: a local keyDown monitor scoped to this view's window, leaving text fields
/// and modified keys alone.
struct KeyMonitor: NSViewRepresentable {
    let m: Model

    final class Coordinator { var monitor: Any? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak v, m] e in
            guard let w = v?.window, e.window === w, !(w.firstResponder is NSText),
                  e.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return e }
            switch e.keyCode {
            case 123: m.move(photo: -1)
            case 124: m.move(photo: 1)
            case 126: m.move(stock: -1)
            case 125: m.move(stock: 1)
            case 36, 76: m.developCurrent()
            default: return e
            }
            return nil
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
    static func dismantleNSView(_ v: NSView, coordinator: Coordinator) {
        coordinator.monitor.map(NSEvent.removeMonitor)
    }
}

/// A stock in the list: amber when chosen, a faint lift on hover.
struct StockRow: View {
    @EnvironmentObject var m: Model
    let index: Int
    var focused: FocusState<Bool>.Binding
    @State private var hover = false

    var body: some View {
        let on = index == m.currentStock
        let stock = index >= 0 ? m.stocks[index] : nil
        let title = stock?.name ?? "Original"
        let sub = stock.map { FilmLook.forStock($0.id, name: $0.name).maker } ?? "No film look"
        HStack(spacing: 10) {
            FilmSpriteView(id: stock?.id, name: stock?.name, scale: 1.5)
            VStack(alignment: .leading, spacing: 5) {
                PixelText(text: title, px: 2, color: on ? Pix.ink : Pix.text)
                PixelText(text: sub, px: 1, color: on ? Pix.ink.opacity(0.75) : Pix.dim)
            }
            Spacer(minLength: 0)
            if index >= 0 {
                StarView(on: m.isFavourite(index), dark: on)
                    .onTapGesture { m.toggleFavourite(index); focused.wrappedValue = true }
                    .accessibilityLabel(m.isFavourite(index) ? "Remove favourite" : "Add favourite")
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background {
            if on { Color.clear.amberFill() }
            else if hover { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Pix.text.opacity(0.08)) }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { m.currentStock = index; focused.wrappedValue = true }
    }
}
