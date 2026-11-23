import SwiftUI

/// Your sticker book. Flip a card to see a short fact about the place.
struct StickersView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: String?
    @State private var flipped: Set<String> = []
    @State private var dealt = false
    @State private var showPostcard = false

    var body: some View {
        let t = model.strings
        let all = model.collectedStickers
        let collections = Dictionary(grouping: all, by: { $0.sticker.collection }).map { ($0.key, $0.value.count) }.sorted { $0.0 < $1.0 }
        let shown = all.filter { filter == nil || $0.sticker.collection == filter }

        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(t("stickers.tapToFlip")).font(.subheadline).foregroundStyle(Palette.stone).padding(.horizontal, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(t("stickers.all", "\(all.count)"), on: filter == nil) { filter = nil }
                        ForEach(collections, id: \.0) { name, n in chip("\(name) · \(n)", on: filter == name) { filter = name } }
                    }
                    .padding(.horizontal, 4)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(shown.enumerated()), id: \.element.sticker.id) { i, item in
                        FlipCard(sticker: item.sticker, photo: model.stickerPhoto(item.sticker), place: model.site.place(id: item.record.placeID)?.name ?? "",
                                 date: item.record.date, isNew: model.isNew(item.sticker), flipped: flipped.contains(item.sticker.id),
                                 newLabel: t("stickers.new"), backTitle: t("stickers.fact"))
                            .onTapGesture {
                                Haptics.tap()
                                withAnimation(Motion.glide) { flipped.formSymmetricDifference([item.sticker.id]) }
                            }
                            .opacity(dealt ? 1 : 0).offset(y: dealt ? 0 : 30).rotationEffect(.degrees(dealt ? 0 : (i % 2 == 0 ? -3 : 3)))
                            .animation(Motion.pop.delay(0.15 + Double(i) * 0.13), value: dealt)
                    }
                }

                if all.isEmpty {
                    Text(t("stickers.empty")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.stone)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                Button { showPostcard = true } label: {
                    HStack(spacing: 14) {
                        CoverImage(model.site.postcardImage).frame(width: 56, height: 64).clipShape(.rect(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 3)).rotationEffect(.degrees(-6))
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("postcard.make")).font(Typeface.display(17)).foregroundStyle(.white)
                            Text(t("postcard.note")).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 18).frame(minHeight: 96)
                    .background(Palette.mare, in: .rect(cornerRadius: 24))
                }
                .opacity(dealt ? 1 : 0).animation(.easeOut.delay(0.5), value: dealt)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .background(Palette.calce)
        .navigationTitle(t("stickers.title"))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton(style: .toolbar) } }
        }
        .onAppear { dealt = false; DispatchQueue.main.async { dealt = true } }
        .sheet(isPresented: $showPostcard) { PostcardView() }
        #if DEBUG
        .task { if DebugLaunch.screen == "postcard" { showPostcard = true } }
        #endif
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(Motion.glide) { action() } }) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Palette.calce : Palette.piperno)
                .padding(.horizontal, 14).frame(height: 34)
                .background(on ? Palette.piperno : Palette.card, in: .capsule)
                .overlay(Capsule().stroke(on ? .clear : Palette.hair, lineWidth: 1.5))
        }
    }
}

private struct FlipCard: View {
    let sticker: Sticker
    let photo: UIImage?
    let place: String
    let date: Date
    let isNew: Bool
    let flipped: Bool
    let newLabel: String
    let backTitle: String

    var body: some View {
        ZStack {
            front.opacity(flipped ? 0 : 1)
            back.opacity(flipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (0, 1, 0))
        }
        .frame(height: 236)
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (0, 1, 0), perspective: 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flipped ? sticker.back : "\(sticker.title), \(place)")
        .accessibilityHint("Double-tap to flip")
        .accessibilityAddTraits(.isButton)
    }

    private var front: some View {
        VStack(spacing: 10) {
            StickerArt(sticker: sticker, border: 6, photo: photo).frame(width: 118, height: 104)
            Text(sticker.title).font(Typeface.display(17)).foregroundStyle(Palette.piperno).multilineTextAlignment(.center)
            Text(place).font(.system(size: 12)).foregroundStyle(Palette.stone).multilineTextAlignment(.center)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.card, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.hair, lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            if isNew {
                Text(newLabel).font(.system(size: 10, weight: .heavy)).kerning(0.6).foregroundStyle(Palette.onTufo)
                    .padding(.horizontal, 8).frame(height: 22).background(Palette.tufo, in: .capsule).padding(12)
            }
        }
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(backTitle).font(.system(size: 10, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(Palette.calce)
            Text(sticker.back).font(Typeface.hand(19)).foregroundStyle(Palette.calce)
            Spacer()
            Text("\(place) · \(date.formatted(.dateTime.day().month()))").font(.system(size: 12)).foregroundStyle(Palette.calce.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Palette.piperno, in: .rect(cornerRadius: 24))
    }
}
