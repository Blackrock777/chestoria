import SwiftUI
import UIKit

// MARK: - Photo framing

/// Aspect-fill maths with a movable anchor and extra zoom, so a normalised point in the photo
/// can be mapped to a point on screen (used by the recogniser box and the look-closer hunt).
struct CoverLayout: Equatable {
    let imageSize: CGSize
    let container: CGSize
    var anchor: CGPoint = .init(x: 0.5, y: 0.5)
    var zoom: CGFloat = 1

    var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(container.width / imageSize.width, container.height / imageSize.height) * zoom
    }
    var displaySize: CGSize { CGSize(width: imageSize.width * scale, height: imageSize.height * scale) }
    var origin: CGPoint {
        CGPoint(x: (container.width - displaySize.width) * anchor.x, y: (container.height - displaySize.height) * anchor.y)
    }
    func point(_ p: NormalizedPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * displaySize.width, y: origin.y + p.y * displaySize.height)
    }
    func rect(_ r: NormalizedRect) -> CGRect {
        let o = point(.init(x: r.x, y: r.y))
        return CGRect(x: o.x, y: o.y, width: r.w * displaySize.width, height: r.h * displaySize.height)
    }
}

/// A photo that fills its container, framed by `anchor` and `zoom`.
/// The source can be content (`ImageRef`, asset or URL) or a photo the person just took.
struct CoverImage: View {
    enum Source { case ref(ImageRef), image(UIImage) }
    let source: Source
    var anchor: NormalizedPoint = .init(x: 0.5, y: 0.5)
    var zoom: CGFloat = 1
    @State private var loaded: UIImage?

    init(_ ref: ImageRef, anchor: NormalizedPoint = .init(x: 0.5, y: 0.5), zoom: CGFloat = 1) {
        source = .ref(ref); self.anchor = anchor; self.zoom = zoom
    }
    init(image: UIImage, anchor: NormalizedPoint = .init(x: 0.5, y: 0.5), zoom: CGFloat = 1) {
        source = .image(image); self.anchor = anchor; self.zoom = zoom
    }

    private var current: UIImage? {
        switch source {
        case .image(let i): i
        case .ref(let r): loaded ?? ImageLoader.shared.cached(r)
        }
    }
    private var key: String {
        switch source { case .image(let i): "img-\(ObjectIdentifier(i).hashValue)"; case .ref(let r): "\(r)" }
    }

    var body: some View {
        GeometryReader { geo in
            if let img = current {
                let l = CoverLayout(imageSize: img.size, container: geo.size, anchor: CGPoint(x: anchor.x, y: anchor.y), zoom: zoom)
                Image(uiImage: img).resizable()
                    .frame(width: l.displaySize.width, height: l.displaySize.height)
                    .offset(x: l.origin.x, y: l.origin.y)
            } else {
                Palette.sunk.overlay(ProgressView())
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: key) { if current == nil, case .ref(let r) = source { loaded = await ImageLoader.shared.load(r) } }
    }
}

/// Shows only `crop` (normalised) of a photo, filling the frame.
struct CroppedImage: View {
    let ref: ImageRef
    let crop: NormalizedRect
    @State private var loaded: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let img = loaded ?? ImageLoader.shared.cached(ref) {
                let sz = img.size
                let s = max(geo.size.width / (crop.w * sz.width), geo.size.height / (crop.h * sz.height))
                let cx = (crop.x + crop.w / 2) * sz.width * s, cy = (crop.y + crop.h / 2) * sz.height * s
                Image(uiImage: img).resizable()
                    .frame(width: sz.width * s, height: sz.height * s)
                    .offset(x: geo.size.width / 2 - cx, y: geo.size.height / 2 - cy)
            } else {
                Palette.sunk
            }
        }
        .clipped()
        .task(id: "\(ref)") { if ImageLoader.shared.cached(ref) == nil { loaded = await ImageLoader.shared.load(ref) } }
    }
}

// MARK: - Stickers

/// A slightly wobbly die-cut outline.
nonisolated struct BlobShape: Shape {
    var seed: Double = 0.7
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = 72
        for i in 0..<n {
            let a = 2 * Double.pi * Double(i) / Double(n)
            let r = 0.47 + 0.025 * sin(3 * a + seed) + 0.015 * cos(5 * a)
            let pt = CGPoint(x: rect.midX + cos(a) * r * rect.width * 0.98 * 1.02, y: rect.midY + sin(a) * r * rect.height * 0.98 * 1.02)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

struct StickerArt: View {
    @Environment(AppModel.self) private var model
    let sticker: Sticker
    var border: CGFloat = 8
    /// -1...1 tilt used to move the sheen.
    var sheen: CGFloat = 0
    /// The person's own photo; when present the sticker is cut from it instead of the content image.
    var photo: UIImage? = nil

    var body: some View {
        Group {
            if let photo {
                CoverImage(image: photo)
            } else if let place = model.catalog.sites.lazy.compactMap({ $0.placeOwning(stickerID: sticker.id) }).first {
                // Nearby/map stories use the selected place, never an unrelated detail crop.
                CoverImage(place.cameraImage, anchor: place.cameraAnchor)
            } else {
                CroppedImage(ref: sticker.image, crop: sticker.crop)
            }
        }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.38), .init(color: .white.opacity(0.5), location: 0.5), .init(color: .clear, location: 0.62)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .offset(x: sheen * 120)
                    .blendMode(.softLight)
            }
            .clipShape(BlobShape())
            .overlay(BlobShape().stroke(.white, lineWidth: border))
            .shadow(color: Color(red: 0.24, green: 0.16, blue: 0).opacity(0.4), radius: 16, y: 12)
            .accessibilityLabel(Text(sticker.title))
    }
}

// MARK: - Glass, pills, buttons

struct GlassChip<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 10) { content }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).frame(height: 44)
            .glassEffect(.regular, in: .capsule)
    }
}

struct LiveDot: View {
    @State private var ping = false
    var body: some View {
        Circle().fill(Palette.tufo).frame(width: 10, height: 10)
            .background(Circle().stroke(Palette.tufo.opacity(ping ? 0 : 0.7), lineWidth: 2).scaleEffect(ping ? 2.6 : 1))
            .onAppear { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { ping = true } }
    }
}

struct VerifiedPill: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .bold)).textCase(.uppercase).kerning(0.6)
            .foregroundStyle(Palette.maiolica)
            .padding(.horizontal, 12).frame(height: 28)
            .background(Palette.maiolicaSoft, in: .capsule)
    }
}

struct TagPill: View {
    let text: String
    var fill: Color = Palette.tufoSoft
    var ink: Color = Palette.piperno
    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold)).textCase(.uppercase).kerning(0.6)
            .foregroundStyle(ink).padding(.horizontal, 12).frame(height: 28).background(fill, in: .capsule)
    }
}

enum CTAStyleKind { case dark, tufo, light }

struct CTAButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var kind: CTAStyleKind = .dark
    var shine = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(kind == .dark ? Palette.calce : kind == .tufo ? Palette.onTufo : Color(red: 0.17, green: 0.19, blue: 0.18))
            .background(kind == .dark ? Palette.piperno : kind == .tufo ? Palette.tufo : Color(red: 0.96, green: 0.96, blue: 0.94), in: .capsule)
            .overlay { if shine { ShineSweep().clipShape(.capsule) } }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.82 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ShineSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var x: CGFloat = -1.4
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 70).offset(x: x * geo.size.width)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduce else { return }
            withAnimation(.easeInOut(duration: 1.1).delay(1.2).repeatForever(autoreverses: false).delay(1.7)) { x = 1.4 }
        }
    }
}

/// Answer button with a physical "press" depth (the idea we borrow from Duolingo).
struct AnswerButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var labelSize = 18.0
    var selected: Bool
    var key: String
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed && !reduceMotion
        HStack {
            configuration.label
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(Palette.piperno)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(key).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? .white : Palette.stone)
                .frame(width: 28, height: 28)
                .background(Circle().fill(selected ? Palette.piperno : .clear))
                .overlay(Circle().stroke(selected ? Palette.piperno : Palette.hair, lineWidth: 1.5))
        }
        .padding(.leading, 18).padding(.trailing, 16).padding(.vertical, 10)
        .frame(minHeight: 62)
        .background(RoundedRectangle(cornerRadius: 20).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Palette.piperno : Palette.hair, lineWidth: 1.5))
        .background(RoundedRectangle(cornerRadius: 20).fill(selected ? Palette.piperno : Palette.hair).offset(y: down ? 0 : 3))
        .offset(y: down ? 3 : 0)
        .opacity(configuration.isPressed && reduceMotion ? 0.82 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.7), value: down)
    }
}

// MARK: - Theory seal

struct TheoryCard: View {
    let theory: Theory
    var stamped: Bool
    var body: some View {
        HStack(spacing: 14) {
            Text(theory.label).font(.system(size: 10, weight: .heavy)).kerning(0.5)
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Palette.pompei).shadow(color: .black.opacity(0.15), radius: 0, y: -3))
                .overlay(Circle().stroke(Palette.pompei.opacity(0.25), lineWidth: 4).padding(-4))
                .rotationEffect(.degrees(stamped ? -12 : -40))
                .scaleEffect(stamped ? 1 : 2.2)
                .opacity(stamped ? 1 : 0)
            Text("\(Text(theory.lead).bold()) \(theory.text)")
                .font(.system(size: 15)).foregroundStyle(Palette.piperno)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.pompeiSoft, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Camera furniture

struct Reticle: View {
    var color: Color = .white
    var line: CGFloat = 4
    var corner: CGFloat = 38
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, c = corner
            Path { p in
                p.move(to: .init(x: 0, y: c)); p.addLine(to: .zero); p.addLine(to: .init(x: c, y: 0))
                p.move(to: .init(x: w - c, y: 0)); p.addLine(to: .init(x: w, y: 0)); p.addLine(to: .init(x: w, y: c))
                p.move(to: .init(x: 0, y: h - c)); p.addLine(to: .init(x: 0, y: h)); p.addLine(to: .init(x: c, y: h))
                p.move(to: .init(x: w - c, y: h)); p.addLine(to: .init(x: w, y: h)); p.addLine(to: .init(x: w, y: h - c))
            }
            .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.35), radius: 4)
        }
    }
}

struct ShutterButton: View {
    var enabled = true
    var glowing = false
    var label = "Take photo"
    let action: () -> Void
    @State private var glow = false
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(.white, lineWidth: 5).frame(width: 84, height: 84)
                Circle().fill(Palette.tufo).frame(width: 66, height: 66)
                    .shadow(color: Palette.tufo.opacity(glowing && glow ? 0.8 : 0), radius: 16)
                    .scaleEffect(glowing && glow ? 1.05 : 1)
            }
        }
        .buttonStyle(ShutterPress())
        .disabled(!enabled).opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
        .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { glow = true } }
    }
    private struct ShutterPress: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}

/// A brief white flash, triggered by changing `trigger`.
struct FlashOverlay: View {
    var trigger: Int
    @State private var opacity: Double = 0
    var body: some View {
        Color.white.opacity(opacity).ignoresSafeArea().allowsHitTesting(false)
            .onChange(of: trigger) {
                opacity = 1
                withAnimation(.easeOut(duration: 0.45)) { opacity = 0 }
            }
    }
}

struct CloseButton: View {
    let action: () -> Void
    @Environment(AppModel.self) private var model
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(model.strings("common.close"))
    }
}
