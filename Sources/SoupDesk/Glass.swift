import SwiftUI
import AppKit

// MARK: - Glass: Liquid Glass on macOS 26+, the system blur before that
//
// Three materials and no more: clear glass for chrome floating over the photo,
// amber glass for the one action, and wells for groups inside glass (never glass on glass).

enum Panel {
    static let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
}

/// The title bar is hidden, so let the backdrop move the window.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { v.window?.isMovableByWindowBackground = true }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

extension View {
    @ViewBuilder
    func glass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            let g = tint.map { Glass.regular.tint($0) } ?? .regular
            glassEffect(interactive ? g.interactive() : g, in: shape)
        } else {
            background(tint.map { AnyShapeStyle($0.opacity(0.86)) } ?? AnyShapeStyle(.ultraThinMaterial), in: shape)
                .overlay(shape.stroke(Pix.text.opacity(0.14), lineWidth: 1))
        }
    }

    /// A group inside glass: darker, no blur of its own.
    func well(_ radius: CGFloat = 14) -> some View {
        let r = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(.black.opacity(0.22), in: r).overlay(r.stroke(Pix.text.opacity(0.08), lineWidth: 1))
    }

    /// The amber selection inside a panel: solid, not glass, so it doesn't stack on the panel's glass.
    func amberFill(_ radius: CGFloat = 14) -> some View {
        let r = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Pix.accent.opacity(0.9), in: r)
            .overlay(r.stroke(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
    }
}

/// Capsule button floating over the photo. `primary` is the amber one: Develop.
struct GlassButton: View {
    let title: String
    var primary = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            PixelText(text: title, px: 2, color: primary ? Pix.ink : Pix.text)
                .padding(.horizontal, 18).frame(height: 38)
                .contentShape(Capsule())
                .background(primary ? Pix.accent.opacity(0.9) : .clear, in: Capsule())   // amber even when the window is inactive
                .glass(in: Capsule(), interactive: true)
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Segment inside a well (Get stocks / Import / Make): lights up on hover.
struct WellButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            PixelText(text: title, px: 1, color: enabled ? Pix.text : Pix.line)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(hover && enabled ? Pix.text.opacity(0.12) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .onHover { hover = $0 }
    }
}

/// The 7D's speed band: the film speed on the roll's own colour, the one splash of colour on screen.
struct SpeedBand: View {
    let look: FilmLook?
    var body: some View {
        let colour = look?.band ?? 0x8a8a8a
        let r = Double(colour >> 16 & 0xff), g = Double(colour >> 8 & 0xff), b = Double(colour & 0xff)
        let light = 0.299 * r + 0.587 * g + 0.114 * b > 150
        let iso = look?.iso ?? ""
        let text = look == nil ? "As shot" : iso.allSatisfy(\.isNumber) ? "Film speed \(iso)" : iso
        PixelText(text: text, px: 2, color: light ? Pix.ink : Pix.text)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color(hex: colour), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
    }
}
