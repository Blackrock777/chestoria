import SwiftUI

/// Lists the sources behind a story. Every fact in CheStoria has at least one.
struct SourcesSheet: View {
    let factCheck: FactCheck
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = model.strings
        NavigationStack {
            List {
                Section {
                    ForEach(factCheck.sources, id: \.url) { source in
                        Link(destination: source.url) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.piperno)
                                Text(source.url.host() ?? "").font(.system(size: 13)).foregroundStyle(Palette.azzurro)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("sources.note"))
                        Text(t("sources.checked", factCheck.checkedOn))
                    }
                }
            }
            .navigationTitle(t("sources.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
