import PhotosUI
import SwiftUI

/// A real postcard: your own photo on the left (from your library, or the site's photo),
/// a handwritten-style message and a stamp on the right. Rendered with ImageRenderer and shared.
struct PostcardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picked: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var message = ""
    @State private var rendered: Image?
    @FocusState private var writing: Bool

    var body: some View {
        let t = model.strings
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    card
                        .aspectRatio(1.5, contentMode: .fit)
                        .overlay(alignment: .topLeading) {
                            // The photo half is the button: tap it to choose your own.
                            GeometryReader { geo in
                                PhotosPicker(selection: $picked, matching: .images) {
                                    Color.clear.contentShape(Rectangle())
                                }
                                .frame(width: geo.size.width * 0.5, height: geo.size.height)
                                .accessibilityLabel(t("postcard.changePhoto"))
                            }
                        }
                        .shadow(color: .black.opacity(0.2), radius: 18, y: 10)

                    PhotosPicker(selection: $picked, matching: .images) {
                        Label(t("postcard.changePhoto"), systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered).tint(Palette.azzurro)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("postcard.messageLabel")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        TextField(t("postcard.messagePlaceholder"), text: $message, axis: .vertical)
                            .lineLimit(3...5)
                            .focused($writing)
                            .padding(14)
                            .background(Palette.card, in: .rect(cornerRadius: 14))
                    }

                    if let rendered {
                        ShareLink(item: rendered, preview: SharePreview(t("postcard.greeting", model.site.city), image: rendered)) {
                            Label(t("postcard.share"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CTAButtonStyle(kind: .tufo))
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.calce)
            .navigationTitle(t("stickers.postcard"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(t("common.done")) { writing = false } }
            }
        }
        .task(id: renderKey) { render() }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { photo = image }
                picked = nil
            }
        }
    }

    private var card: PostcardCard {
        PostcardCard(site: model.site, photo: photo, greeting: model.strings("postcard.greeting", model.site.city),
                     message: message.isEmpty ? model.strings("postcard.messagePlaceholder") : message, placeholder: message.isEmpty)
    }

    private var renderKey: String { "\(message)|\(photo.map { ObjectIdentifier($0).hashValue } ?? 0)" }

    private func render() {
        let full = PostcardCard(site: model.site, photo: photo, greeting: model.strings("postcard.greeting", model.site.city),
                                message: message, placeholder: false)
            .frame(width: 1500, height: 1000).environment(\.colorScheme, .light)
        let r = ImageRenderer(content: full); r.scale = 1
        if let ui = r.uiImage { rendered = Image(uiImage: ui) }
    }
}

private struct PostcardCard: View {
    let site: SiteContent
    let photo: UIImage?
    let greeting: String
    let message: String
    let placeholder: Bool

    private let ink = Color(red: 0.17, green: 0.19, blue: 0.18)

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 1500
            HStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    if let photo { CoverImage(image: photo) } else { CoverImage(site.postcardImage) }
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    Text(greeting).font(.system(size: 64 * k, weight: .bold, design: .serif)).italic()
                        .foregroundStyle(.white).padding(44 * k)
                }
                .frame(width: geo.size.width * 0.5)
                .clipped()

                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            Spacer()
                            Stamp(image: site.postcardImage, city: site.city, k: k)
                        }
                        Text(message)
                            .font(.system(size: 38 * k, weight: .regular, design: .serif)).italic()
                            .foregroundStyle(placeholder ? ink.opacity(0.35) : ink)
                            .lineSpacing(10 * k)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 30 * k)
                        Spacer(minLength: 0)
                        // Address lines, like the back of a real postcard.
                        VStack(spacing: 62 * k) {
                            ForEach(0..<3, id: \.self) { _ in Rectangle().fill(ink.opacity(0.18)).frame(height: 2 * k) }
                        }
                        .padding(.leading, 220 * k).padding(.bottom, 40 * k)
                        Text("CheStoria · \(site.city)").font(.system(size: 24 * k, weight: .semibold)).foregroundStyle(ink.opacity(0.45))
                    }
                    .padding(50 * k)
                }
                .overlay(alignment: .leading) { Rectangle().fill(ink.opacity(0.12)).frame(width: 2 * k).padding(.vertical, 60 * k) }
            }
            .background(Color(red: 0.98, green: 0.97, blue: 0.94))
        }
        .clipShape(.rect(cornerRadius: 18))
    }
}

/// A small perforated stamp with the site's photo.
private struct Stamp: View {
    let image: ImageRef
    let city: String
    let k: CGFloat
    var body: some View {
        CoverImage(image)
            .frame(width: 150 * k, height: 180 * k)
            .overlay(alignment: .bottom) {
                Text(city.uppercased()).font(.system(size: 18 * k, weight: .heavy)).kerning(1).foregroundStyle(.white)
                    .padding(.bottom, 10 * k).shadow(radius: 3)
            }
            .padding(10 * k)
            .background(.white)
            .overlay(Rectangle().stroke(style: StrokeStyle(lineWidth: 6 * k, dash: [2 * k, 8 * k])).foregroundStyle(Color(red: 0.98, green: 0.97, blue: 0.94)))
            .rotationEffect(.degrees(4))
            .shadow(color: .black.opacity(0.15), radius: 4 * k, y: 2 * k)
    }
}
