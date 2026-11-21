import SwiftUI

/// "About this story": where the facts come from and who took the photos.
/// Kept out of the story itself, one tap away behind the ⓘ button (as in Apple News, Wikipedia and Google Arts & Culture).
struct StoryInfoSheet: View {
    let place: Place
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = model.strings
        let story = place.story
        let photos = place.allImages.compactMap(Credits.shared.photo(for:))
        NavigationStack {
            List {
                if let fc = story?.factCheck {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fc.status == .verified ? t("reveal.verified", story?.source ?? "") : t("reveal.sourced", "\(fc.sources.count)"))
                                    .font(.headline)
                                Text(t("sources.checked", fc.checkedOn)).font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.maiolica).font(.title2)
                        }
                        .padding(.vertical, 4)
                    }
                    Section {
                        ForEach(fc.sources, id: \.url) { source in
                            Link(destination: source.url) {
                                LinkRow(title: source.title, detail: source.url.host() ?? "")
                            }
                        }
                    } header: { Text(t("about.sources")) } footer: { Text(t("sources.note")) }
                }
                if !photos.isEmpty {
                    Section(t("about.photos")) {
                        ForEach(photos, id: \.asset) { PhotoCreditRow(photo: $0) }
                    }
                }
            }
            .navigationTitle(t("about.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Profile → About → Acknowledgements: every photo credit and licence notice, like Settings → Legal on iPhone.
struct AcknowledgementsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let t = model.strings
        let credits = Credits.shared
        List {
            Section { Text(t("ack.note")).font(.footnote).foregroundStyle(.secondary) }
            ForEach(model.catalog.sites) { site in
                let assets = Set(site.places.flatMap(\.allImages) + [site.postcardImage, site.welcome.image])
                let photos = credits.photos.filter { assets.contains(.asset($0.asset)) }
                if !photos.isEmpty {
                    Section(site.city) { ForEach(photos, id: \.asset) { PhotoCreditRow(photo: $0) } }
                }
            }
            Section(t("ack.notices")) {
                ForEach(credits.notices, id: \.title) { n in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.title).font(.headline)
                        Text(n.text).font(.subheadline).foregroundStyle(.secondary)
                        if let url = n.url { Link(url.host() ?? url.absoluteString, destination: url).font(.subheadline) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(t("ack.title"))
    }
}

private struct PhotoCreditRow: View {
    let photo: Credits.Photo
    var body: some View {
        let row = HStack(spacing: 12) {
            CoverImage(.asset(photo.asset)).frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 8))
            LinkRow(title: photo.title, detail: photo.line, showsArrow: photo.url != nil)
        }
        if let url = photo.url ?? photo.licenceURL { Link(destination: url) { row } } else { row }
    }
}

private struct LinkRow: View {
    let title: String
    let detail: String
    var showsArrow = true
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if showsArrow { Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .contentShape(Rectangle())
    }
}
