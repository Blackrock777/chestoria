import SwiftUI

/// Switch between sites in the catalog (Pompeii, Naples …). Each keeps its own trip.
struct SitePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = model.strings
        NavigationStack {
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// The last recognitions with every distance, for tuning thresholds on site.
struct RecognitionLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(PlaceMatcher.self) private var matcher

    var body: some View {
        let t = model.strings
        List {
            Section { Text(t("profile.recognitionLogNote")).font(.system(size: 13)).foregroundStyle(Palette.stone) }
            if matcher.log.isEmpty { Text(t("profile.logEmpty")).foregroundStyle(Palette.stone) }
            ForEach(matcher.log) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.outcome).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 12)).foregroundStyle(Palette.stone)
                    }
                    Text(entry.ranked.map { "\($0.id) \(String(format: "%.3f", $0.distance))" }.joined(separator: " · "))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.stone)
                    Text(entry.backend == .vision ? "Vision" : "Descriptor").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.azzurro)
                }
            }
        }
        .navigationTitle(t("profile.recognitionLog"))
    }
}
