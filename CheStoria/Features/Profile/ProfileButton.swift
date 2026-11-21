import SwiftUI

/// Round avatar that opens the profile. Shows initials when signed in, a person icon otherwise.
struct ProfileButton: View {
    enum Style { case glass, plain, toolbar }
    var style: Style = .plain
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account

    var body: some View {
        Button { Haptics.tap(); model.showProfile = true } label: {
            if style == .toolbar {
                // In a navigation bar the system draws the glass; we only supply the symbol or initials.
                if let user = account.user {
                    Text(user.initials).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Palette.onTufo)
                        .frame(width: 32, height: 32).background(Circle().fill(Palette.tufo))
                } else {
                    Image(systemName: "person.crop.circle")
                }
            } else {
            Group {
                if let user = account.user {
                    Text(user.initials).font(Typeface.display(15)).foregroundStyle(Palette.onTufo)
                        .frame(width: 44, height: 44).background(Circle().fill(Palette.tufo))
                } else {
                    Image(systemName: "person.fill").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(style == .glass ? .white : Palette.piperno)
                        .frame(width: 44, height: 44)
                        .background { if style == .plain { Circle().fill(Palette.card).overlay(Circle().stroke(Palette.hair, lineWidth: 1.5)) } }
                }
            }
            }
        }
        .modifier(GlassIf(on: style == .glass && account.user == nil))
        .accessibilityLabel(model.strings("profile.open"))
    }

    private struct GlassIf: ViewModifier {
        let on: Bool
        func body(content: Content) -> some View {
            if on { content.glassEffect(.regular.interactive(), in: .circle) } else { content }
        }
    }
}

/// Picks the story language. Only languages the content actually has are offered.
struct LanguagePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = model.strings
        NavigationStack {
            List {
                Section {
                    ForEach(model.languages, id: \.self) { code in
                        Button {
                            Haptics.tap()
                            withAnimation { model.setLanguage(code) }
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.languageName(code)).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.piperno)
                                    Text(Locale.current.localizedString(forLanguageCode: code) ?? code).font(.system(size: 13)).foregroundStyle(Palette.stone)
                                }
                                Spacer()
                                if code == model.language { Image(systemName: "checkmark").foregroundStyle(Palette.azzurro).fontWeight(.semibold) }
                            }
                        }
                    }
                } footer: { Text(t("lang.note")) }
            }
            .navigationTitle(t("lang.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
