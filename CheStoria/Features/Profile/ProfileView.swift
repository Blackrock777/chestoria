import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if account.isSignedIn { SignedInView() } else { SignInView() }
            }
            .navigationTitle(model.strings("profile.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(model.strings("common.done")) { dismiss() } } }
            .background(Palette.calce)
        }
        .animation(Motion.glide, value: account.isSignedIn)
    }
}

// MARK: - Signed out

private struct SignInView: View {
    enum Mode: Hashable { case signIn, create }
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.colorScheme) private var scheme
    @State private var mode: Mode = .create
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    enum Field { case name, email, password }

    var body: some View {
        let t = model.strings
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "person.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(Palette.stone)
                        .frame(width: 64, height: 64).background(Circle().fill(Palette.sunk))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("profile.guest")).font(Typeface.display(24)).foregroundStyle(Palette.piperno)
                        Text(t("profile.guestNote")).font(.system(size: 14)).foregroundStyle(Palette.stone)
                    }
                }
                .padding(.top, 8)

                SignInWithAppleButton(mode == .create ? .signUp : .signIn) { req in
                    req.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await account.handleApple(result) }
                }
                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                .frame(height: 54).clipShape(.capsule)

                HStack { line; Text(t("profile.or")).font(.system(size: 13)).foregroundStyle(Palette.stone); line }

                Picker("", selection: $mode) {
                    Text(t("profile.createAccount")).tag(Mode.create)
                    Text(t("profile.signIn")).tag(Mode.signIn)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 10) {
                    if mode == .create {
                        field(t("profile.name"), text: $name, kind: .name)
                            .textContentType(.name).submitLabel(.next)
                    }
                    field(t("profile.email"), text: $email, kind: .email)
                        .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.next)
                    SecureField(t("profile.password"), text: $password)
                        .textContentType(mode == .create ? .newPassword : .password)
                        .focused($focus, equals: .password).submitLabel(.go)
                        .onSubmit(submit)
                        .modifier(FieldStyle(focused: focus == .password))
                    if mode == .create {
                        Text(t("profile.passwordHint")).font(.system(size: 12)).foregroundStyle(Palette.stone).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let error = account.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(.system(size: 14)).foregroundStyle(Palette.pompei)
                        .transition(.opacity)
                }

                Button(action: submit) {
                    if account.isBusy { ProgressView().tint(Palette.calce) } else { Text(mode == .create ? t("profile.createAccount") : t("profile.signIn")) }
                }
                .buttonStyle(CTAButtonStyle(kind: .dark))
                .disabled(account.isBusy || email.isEmpty || password.isEmpty || (mode == .create && name.isEmpty))
                .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)

                if !account.isServerBacked {
                    Label(t("profile.localNote"), systemImage: "lock.fill").font(.system(size: 12)).foregroundStyle(Palette.stone)
                }
            }
            .padding(20)
            .animation(Motion.glide, value: mode)
            .animation(.easeOut, value: account.errorMessage)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: mode) { account.errorMessage = nil }
    }

    private var line: some View { Rectangle().fill(Palette.hair).frame(height: 1) }

    private func field(_ title: String, text: Binding<String>, kind: Field) -> some View {
        TextField(title, text: text)
            .focused($focus, equals: kind)
            .onSubmit { focus = kind == .name ? .email : .password }
            .modifier(FieldStyle(focused: focus == kind))
    }

    private func submit() {
        focus = nil
        Task {
            if mode == .create { await account.signUp(name: name, email: email, password: password) }
            else { await account.signIn(email: email, password: password) }
            if account.isSignedIn { password = "" }
        }
    }
}

private struct FieldStyle: ViewModifier {
    let focused: Bool
    func body(content: Content) -> some View {
        content.font(.system(size: 17)).padding(.horizontal, 16).frame(height: 54)
            .background(Palette.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(focused ? Palette.azzurro : Palette.hair, lineWidth: focused ? 2 : 1.5))
    }
}

// MARK: - Signed in

private struct SignedInView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Settings.haptics) private var haptics = true
    @AppStorage(Settings.recall) private var recall = true
    @AppStorage(Settings.autoRead) private var autoRead = false
    @State private var editingName = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var showSites = false

    var body: some View {
        @Bindable var model = model
        let t = model.strings
        let user = account.user!
        List {
            Section {
                HStack(spacing: 14) {
                    Text(user.initials).font(Typeface.display(24)).foregroundStyle(Palette.onTufo)
                        .frame(width: 64, height: 64).background(Circle().fill(Palette.tufo))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.displayName).font(Typeface.display(22)).foregroundStyle(Palette.piperno)
                        if let e = user.email { Text(e).font(.system(size: 14)).foregroundStyle(Palette.stone) }
                        Text(t("profile.signedInWith", t(user.provider == .apple ? "profile.providerApple" : "profile.providerEmail")))
                            .font(.system(size: 12)).foregroundStyle(Palette.stone)
                    }
                }
                .padding(.vertical, 6)
                HStack(spacing: 0) {
                    stat("\(model.visitedPlaces.count)", t("profile.places"))
                    Divider()
                    stat("\(model.collectedStickers.count)", t("profile.stickers"))
                    Divider()
                    stat("\(model.recallStats.remembered)/\(model.recallStats.answered)", t("profile.remembered"))
                }
                .frame(height: 56)
            }

            Section(t("profile.settings")) {
                Button { model.showLanguagePicker = true } label: {
                    LabeledContent(t("lang.title"), value: model.languageName(model.language))
                }
                .tint(Palette.piperno)
                Button { showSites = true } label: {
                    LabeledContent(t("profile.site"), value: model.site.city)
                }
                .tint(Palette.piperno)
                Toggle(t("profile.haptics"), isOn: $haptics)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("profile.recall"), isOn: $recall)
                    Text(t("profile.recallNote")).font(.system(size: 12)).foregroundStyle(Palette.stone)
                }
                Toggle(t("profile.autoRead"), isOn: $autoRead)
            }
            .tint(Palette.azzurro)

            Section(t("profile.demo")) {
                Button(t("profile.resetTrip")) { model.resetDemo(); dismiss() }
                Button(t("profile.replayWelcome")) { model.resetOnboarding(); dismiss() }
                NavigationLink(t("profile.recognitionLog")) { RecognitionLogView() }
            }

            Section(t("profile.account")) {
                Button(t("profile.editName")) { newName = user.displayName; editingName = true }
                Button(t("profile.signOut")) { account.signOut() }
                Button(t("profile.delete"), role: .destructive) { confirmDelete = true }
            }

            Section(t("profile.about")) {
                Link(t("profile.credits"), destination: URL(string: "https://github.com/poojatalele/chestoria/blob/main/CREDITS.md")!)
                Text(t("profile.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"))
                    .foregroundStyle(Palette.stone)
            }
        }
        .scrollContentBackground(.hidden)
        .alert(t("profile.editName"), isPresented: $editingName) {
            TextField(t("profile.name"), text: $newName)
            Button(t("common.save")) { account.rename(newName) }
            Button(t("common.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showSites) { SitePicker() }
        .confirmationDialog(t("profile.deleteConfirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(t("profile.delete"), role: .destructive) { Task { await account.deleteAccount() } }
            Button(t("common.cancel"), role: .cancel) {}
        } message: { Text(t("profile.deleteNote")) }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Typeface.display(20)).foregroundStyle(Palette.piperno).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.stone)
        }
        .frame(maxWidth: .infinity)
    }
}
