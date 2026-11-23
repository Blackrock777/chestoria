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

struct SignInView: View {
    enum Mode: Hashable { case signIn, create }
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.colorScheme) private var scheme
    /// In onboarding the screen has its own title, so the "Guest" header is hidden.
    var showsGuestHeader = true
    @State private var mode: Mode = .create
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showRecovery = false
    @FocusState private var focus: Field?
    enum Field { case name, email, password }

    var body: some View {
        let t = model.strings
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if showsGuestHeader {
                HStack(spacing: 14) {
                    Image(systemName: "person.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(Palette.stone)
                        .frame(width: 64, height: 64).background(Circle().fill(Palette.sunk))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("profile.guest")).font(Typeface.display(24)).foregroundStyle(Palette.piperno)
                        Text(t("profile.guestNote")).font(.system(size: 14)).foregroundStyle(Palette.stone)
                    }
                }
                .padding(.top, 8)
                }

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
                    } else {
                        Button(t("recovery.forgot")) {
                            focus = nil
                            account.errorMessage = nil
                            showRecovery = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .tint(Palette.piperno)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .disabled(account.isBusy)
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
        .sheet(isPresented: $showRecovery) {
            PasswordRecoverySheet(email: email) { recoveredEmail in
                email = recoveredEmail
                password = ""
            }
        }
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

// MARK: - Password recovery

private struct PasswordRecoverySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    let onSuccess: (String) -> Void
    @State private var sentTo: String?
    @State private var proof = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isBusy = false
    @State private var complete = false
    @State private var errorKey: String?
    @FocusState private var focus: Field?
    private enum Field { case email, proof, password, confirmation }

    var body: some View {
        let t = model.strings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if complete {
                        Label(t("recovery.success"), systemImage: "checkmark.circle.fill")
                            .font(.headline)
                        Text(t("recovery.successDetail")).foregroundStyle(Palette.stone)
                        Button(t("profile.signIn")) { close() }.buttonStyle(CTAButtonStyle(kind: .dark))
                    } else {
                        Text(t(account.isServerBacked ? "recovery.emailIntro" : "recovery.localIntro"))
                            .foregroundStyle(Palette.stone)
                        if let sentTo {
                            Text(t("recovery.codeSent", sentTo)).font(.subheadline)
                            HStack {
                                Button(t("recovery.changeEmail")) {
                                    self.sentTo = nil
                                    proof = ""
                                    errorKey = nil
                                    focus = .email
                                }
                                Spacer()
                                Button(t("recovery.resend")) { perform(sendCode: true) }
                            }
                            .font(.subheadline.weight(.semibold))
                        } else {
                            TextField(t("profile.email"), text: $email)
                                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textContentType(.emailAddress).focused($focus, equals: .email)
                                .modifier(FieldStyle(focused: focus == .email))
                        }
                        if !account.isServerBacked || sentTo != nil {
                            if account.isServerBacked {
                                TextField(t("recovery.emailCode"), text: $proof)
                                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                                    .focused($focus, equals: .proof).modifier(FieldStyle(focused: focus == .proof))
                            } else {
                                SecureField(t("recovery.keyTitle"), text: $proof)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .focused($focus, equals: .proof).modifier(FieldStyle(focused: focus == .proof))
                            }
                            SecureField(t("recovery.newPassword"), text: $password)
                                .textContentType(.newPassword).focused($focus, equals: .password)
                                .modifier(FieldStyle(focused: focus == .password))
                            SecureField(t("recovery.confirmPassword"), text: $confirmation)
                                .textContentType(.newPassword).focused($focus, equals: .confirmation)
                                .modifier(FieldStyle(focused: focus == .confirmation))
                            Text(t("profile.passwordHint")).font(.footnote).foregroundStyle(Palette.stone)
                        }
                        if let errorKey {
                            Label(t(errorKey), systemImage: "exclamationmark.circle.fill").font(.subheadline).foregroundStyle(Palette.pompei)
                        }
                        let requesting = account.isServerBacked && sentTo == nil
                        Button {
                            perform(sendCode: requesting)
                        } label: {
                            if isBusy { ProgressView().tint(Palette.calce) }
                            else { Text(t(requesting ? "recovery.sendCode" : "recovery.reset")) }
                        }
                        .buttonStyle(CTAButtonStyle(kind: .dark))
                        .disabled(email.isEmpty || (!requesting && (proof.isEmpty || password.isEmpty || confirmation.isEmpty)))
                    }
                }
                .padding(20)
                .disabled(isBusy)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.calce)
            .navigationTitle(t("recovery.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("common.done")) { close() }.disabled(isBusy) } }
        }
        .tint(Palette.piperno)
        .interactiveDismissDisabled(isBusy)
    }

    private func close() {
        if complete { onSuccess(CredentialRules.emailKey(email)) }
        dismiss()
    }

    private func perform(sendCode: Bool) {
        guard !isBusy else { return }
        errorKey = nil
        if !sendCode && password != confirmation { errorKey = "recovery.mismatch"; return }
        focus = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                if sendCode {
                    try await account.sendRecoveryCode(email: email)
                    sentTo = CredentialRules.emailKey(email)
                    proof = ""
                } else {
                    try await account.resetPassword(email: email, proof: proof, newPassword: password)
                    proof = ""
                    password = ""
                    confirmation = ""
                    complete = true
                }
            } catch { errorKey = (error as? AuthError)?.recoveryStringKey ?? "recovery.network" }
        }
    }
}

private struct RecoveryKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var key: String?
    @State private var errorKey: String?
    @State private var isBusy = false
    @FocusState private var focused: Bool

    var body: some View {
        let t = model.strings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let key {
                        Text(t("recovery.saveKey")).font(.headline)
                        Text(key).font(.system(.body, design: .monospaced).weight(.semibold)).textSelection(.enabled)
                            .privacySensitive()
                        Text(t("recovery.saveKeyDetail")).foregroundStyle(Palette.stone)
                    } else {
                        Text(t("recovery.createKeyIntro")).foregroundStyle(Palette.stone)
                        SecureField(t("profile.password"), text: $password).textContentType(.password)
                            .focused($focused).modifier(FieldStyle(focused: focused))
                        if let errorKey {
                            Label(t(errorKey), systemImage: "exclamationmark.circle.fill").font(.subheadline).foregroundStyle(Palette.pompei)
                        }
                        Button {
                            guard !isBusy else { return }
                            focused = false
                            isBusy = true
                            errorKey = nil
                            Task {
                                defer { isBusy = false }
                                do {
                                    key = try await account.createRecoveryKey(currentPassword: password)
                                    password = ""
                                } catch { errorKey = (error as? AuthError)?.recoveryStringKey ?? "recovery.unavailable" }
                            }
                        } label: {
                            if isBusy { ProgressView().tint(Palette.calce) }
                            else { Text(t("recovery.createKey")) }
                        }
                        .buttonStyle(CTAButtonStyle(kind: .dark)).disabled(password.isEmpty || isBusy)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.calce)
            .navigationTitle(t("recovery.keyTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() }.disabled(isBusy) } }
        }
        .tint(Palette.piperno)
        .interactiveDismissDisabled(isBusy)
    }
}

private extension AuthError {
    var recoveryStringKey: String {
        switch self {
        case .invalidEmail: "recovery.invalidEmail"
        case .weakPassword: "profile.passwordHint"
        case .wrongCredentials: "recovery.wrongPassword"
        case .invalidRecoveryKey: "recovery.invalidKey"
        case .invalidRecoveryCode: "recovery.invalidCode"
        case .recoveryRateLimited: "recovery.rateLimited"
        case .recoveryUpdateFailed: "recovery.updateFailed"
        case .recoveryUnavailable, .storageFailed, .notSignedIn: "recovery.unavailable"
        default: "recovery.network"
        }
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
    @AppStorage(Settings.recallHour) private var recallHour = 8
    @AppStorage(Settings.recallMinute) private var recallMinute = 12
    @State private var editingName = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var showSites = false
    @State private var showRecoveryKey = false

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
                if recall {
                    DatePicker(t("profile.recallTime"), selection: Binding(
                        get: { Calendar.current.date(bySettingHour: recallHour, minute: recallMinute, second: 0, of: .now) ?? .now },
                        set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); recallHour = c.hour ?? 8; recallMinute = c.minute ?? 12 }),
                        displayedComponents: .hourAndMinute)
                }
                Toggle(t("profile.autoRead"), isOn: $autoRead)
            }
            .tint(Palette.azzurro)

            #if DEBUG
            // Developer tools: never shown in TestFlight or App Store builds.
            Section("Developer") {
                Button(t("profile.startFresh")) { model.startFresh(); dismiss() }
                NavigationLink(t("profile.recognitionLog")) { RecognitionLogView() }
            }
            #endif

            Section(t("profile.account")) {
                Button(t("profile.editName")) { newName = user.displayName; editingName = true }
                if user.provider == .email && !account.isServerBacked {
                    Button(t("recovery.keyTitle")) { showRecoveryKey = true }
                }
                Button(t("profile.signOut")) { account.signOut() }
                Button(t("profile.delete"), role: .destructive) { confirmDelete = true }
            }

            Section(t("profile.about")) {
                NavigationLink(t("ack.title")) { AcknowledgementsView() }
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
        .sheet(isPresented: $showRecoveryKey) { RecoveryKeySheet() }
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
