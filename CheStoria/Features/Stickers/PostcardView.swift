import SwiftUI

/// A real postcard made from the person's own sticker photos and the lines to retell.
/// Rendered to an image with ImageRenderer and shared with the system share sheet.
struct PostcardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rendered: Image?

    var body: some View {
        let t = model.strings
        NavigationStack {
            VStack(spacing: 18) {
                PostcardCard(site: model.site, items: Array(model.collectedStickers.prefix(4)), photo: model.stickerPhoto, greeting: t("postcard.greeting", model.site.city))
                    .aspectRatio(1.5, contentMode: .fit)
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
                    .padding(.horizontal, 20)
                Text(t("postcard.note")).font(.system(size: 14)).foregroundStyle(Palette.stone).multilineTextAlignment(.center).padding(.horizontal, 30)
                if let rendered {
                    ShareLink(item: rendered, preview: SharePreview(t("postcard.greeting", model.site.city), image: rendered)) {
                        Label(t("postcard.share"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CTAButtonStyle(kind: .tufo)).padding(.horizontal, 20)
                }
                Spacer()
            }
            .padding(.top, 20)
            .background(Palette.calce)
            .navigationTitle(t("stickers.postcard"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } } }
        }
        .task { render() }
    }

    private func render() {
        let card = PostcardCard(site: model.site, items: Array(model.collectedStickers.prefix(4)), photo: model.stickerPhoto,
                                greeting: model.strings("postcard.greeting", model.site.city))
            .frame(width: 1500, height: 1000).environment(\.colorScheme, .light)
        let r = ImageRenderer(content: card); r.scale = 1
        if let ui = r.uiImage { rendered = Image(uiImage: ui) }
    }
}

private struct PostcardCard: View {
    let site: SiteContent
    let items: [(sticker: Sticker, record: CollectedSticker)]
    let photo: (Sticker) -> UIImage?
    let greeting: String

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 1500
            ZStack(alignment: .topLeading) {
                Color(red: 0.98, green: 0.97, blue: 0.94)
                HStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        CoverImage(site.postcardImage)
                        LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                        Text(greeting).font(.custom("Kalam-Bold", size: 64 * k)).foregroundStyle(.white).padding(40 * k)
                    }
                    .frame(width: geo.size.width * 0.5)
                    VStack(alignment: .leading, spacing: 26 * k) {
                        ForEach(Array(items.enumerated()), id: \.element.sticker.id) { i, item in
                            HStack(spacing: 22 * k) {
                                StickerArt(sticker: item.sticker, border: 6 * k, photo: photo(item.sticker))
                                    .frame(width: 130 * k, height: 110 * k).rotationEffect(.degrees(i % 2 == 0 ? -4 : 4))
                                Text(item.sticker.back).font(.custom("Kalam-Bold", size: 30 * k)).foregroundStyle(Color(red: 0.17, green: 0.19, blue: 0.18))
                                    .lineLimit(3).minimumScaleFactor(0.7)
                            }
                        }
                        Spacer(minLength: 0)
                        Text("CheStoria · \(site.city)").font(.custom("BricolageGrotesque-ExtraBold", size: 26 * k)).foregroundStyle(Color(red: 0.42, green: 0.44, blue: 0.43))
                    }
                    .padding(50 * k)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 18))
    }
}
