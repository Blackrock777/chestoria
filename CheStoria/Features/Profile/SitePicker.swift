import SwiftUI

/// Switch between sites in the catalog (Pompeii, Naples …). Each keeps its own trip.
struct SitePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = model.strings
        List(model.catalog.sites) { site in
            Button {
                Haptics.tap(); withAnimation { model.switchSite(to: site.id) }; dismiss()
            } label: {
                HStack(spacing: 14) {
                    CoverImage(site.welcome.image, anchor: site.welcome.imageAnchor).frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.city).font(Typeface.display(19)).foregroundStyle(Palette.piperno)
                        Text(site.name).font(.system(size: 13)).foregroundStyle(Palette.stone)
                    }
                    Spacer()
                    if site.id == model.site.id { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Palette.azzurro) }
                }
            }
        }
        .navigationTitle(t("site.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
