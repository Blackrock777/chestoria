import SwiftUI

/// Your sticker book. Flip a card to see a short fact about the place.
struct StickersView: View {
    @Environment(AppModel.self) private var model
    @State private var flipped: Set<String> = []
    @State private var dealt = false
    @State private var postcardSite: SiteContent?

    var body: some View {
        let t = model.strings
        let collection = model.stickerCollectionID.flatMap(model.catalog.site(id:)) ?? model.site
        let stickers = model.collectedStickers(in: collection)
        let count = stickers.count
        let quantity = count.formatted(.number.locale(Locale(identifier: model.language)))

        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(t(count == 1 ? "stickers.countOne" : "stickers.countMany", quantity))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.piperno)
                    Spacer()
                    if count > 0 {
                        Text(t("stickers.tapToFlip")).font(.subheadline).foregroundStyle(Palette.stone)
                    }
                }
                .padding(.horizontal, 4)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(stickers.enumerated()), id: \.element.sticker.id) { i, item in
                        let place = collection.place(id: item.record.placeID)?.name ?? ""
                        let showingBack = flipped.contains(item.sticker.id)
                        Button {
                            Haptics.tap()
                            withAnimation(Motion.glide) { flipped.formSymmetricDifference([item.sticker.id]) }
                        } label: {
                            FlipCard(sticker: item.sticker, photo: item.record.photoFile.flatMap(StickerPhotos.load),
                                     place: place, date: item.record.date, isNew: i == 0, flipped: showingBack,
                                     newLabel: t("stickers.new"), backTitle: t("stickers.fact"))
                                .contentShape(.interaction, RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showingBack ? item.sticker.back : "\(item.sticker.title), \(place)")
                        .opacity(dealt ? 1 : 0).offset(y: dealt ? 0 : 30).rotationEffect(.degrees(dealt ? 0 : (i % 2 == 0 ? -3 : 3)))
                        .animation(Motion.pop.delay(0.15 + Double(i) * 0.13), value: dealt)
                    }
                }

                if stickers.isEmpty {
                    Text(t("stickers.empty")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.stone)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                Button { postcardSite = collection } label: {
                    HStack(spacing: 14) {
                        CoverImage(collection.postcardImage).frame(width: 56, height: 64).clipShape(.rect(cornerRadius: 8))
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.catalog.sites.count > 1 {
                Picker(t("profile.site"), selection: Binding(get: { collection.id }, set: { model.stickerCollectionID = $0 })) {
                    ForEach(model.catalog.sites) { site in
                        Text(site.city).tag(site.id)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .background(Palette.calce)
            }
        }
        .background(Palette.calce)
        .navigationTitle(t("stickers.title"))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton(style: .toolbar) } }
        }
        .onAppear { dealt = false; DispatchQueue.main.async { dealt = true } }
        .onChange(of: collection.id) { flipped.removeAll() }
        .sheet(item: $postcardSite) { PostcardView(site: $0) }
        #if DEBUG
        .task { if DebugLaunch.screen == "postcard" { postcardSite = collection } }
        #endif
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
        .clipped()
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
