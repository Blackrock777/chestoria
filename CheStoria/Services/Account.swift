import AuthenticationServices
import CommonCrypto
import Foundation
import Security

// MARK: - Model

struct UserAccount: Codable, Equatable, Identifiable, Sendable {
    enum Provider: String, Codable, Sendable { case email, apple }
    let id: String
    var displayName: String
    var email: String?
    let provider: Provider
    let createdAt: Date

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let s = parts.compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
}

enum AuthError: LocalizedError, Equatable {
    case invalidEmail, weakPassword, emptyName, emailInUse, wrongCredentials, appleFailed, notSignedIn, storageFailed, network, confirmEmail

    var errorDescription: String? {
        switch self {
        case .invalidEmail: "Enter a valid email address, like name@example.com."
        case .weakPassword: "Use at least 8 characters, with a letter and a number."
        case .emptyName: "Tell us what to call you."
        case .emailInUse: "There’s already an account with this email. Sign in instead."
        case .wrongCredentials: "That email and password don’t match. Check them and try again."
        case .appleFailed: "Sign in with Apple didn’t finish. Try again."
        case .notSignedIn: "You’re not signed in."
        case .storageFailed: "Your account couldn’t be saved on this device. Try again."
        case .network: "We couldn’t reach the server. Check your connection and try again."
        case .confirmEmail: "Check your inbox and confirm your email, then sign in."
        }
    }
}

/// Any backend can sign people in by implementing this protocol (Firebase, Supabase, your own API).
/// The app only talks to `AccountModel`, which talks to an `AuthService`.
protocol AuthService: AnyObject {
    var currentUser: UserAccount? { get }
    func signUp(name: String, email: String, password: String) async throws -> UserAccount
    func signIn(email: String, password: String) async throws -> UserAccount
    func signInWithApple(userID: String, name: PersonNameComponents?, email: String?, identityToken: String?) async throws -> UserAccount
    func updateDisplayName(_ name: String) throws -> UserAccount
    func signOut()
    func deleteAccount() async throws
}

enum CredentialRules {
    static func isValidEmail(_ s: String) -> Bool {
        s.range(of: #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
    }
    static func isStrongPassword(_ s: String) -> Bool {
        s.count >= 8 && s.rangeOfCharacter(from: .letters) != nil && s.rangeOfCharacter(from: .decimalDigits) != nil
    }
}

// MARK: - Keychain

/// Where account data is kept. The Keychain in the app; memory in tests and previews.
protocol SecureStore: Sendable {
    func data(for account: String) -> Data?
    func set(_ data: Data, for account: String) throws
    func remove(_ account: String)
}

extension SecureStore {
    func codable<T: Decodable>(_ type: T.Type, for account: String) -> T? {
        data(for: account).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    func setCodable<T: Encodable>(_ value: T, for account: String) throws { try set(JSONEncoder().encode(value), for: account) }
}

nonisolated final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()
    init() {}
    func data(for account: String) -> Data? { lock.lock(); defer { lock.unlock() }; return items[account] }
    func set(_ data: Data, for account: String) throws { lock.lock(); items[account] = data; lock.unlock() }
    func remove(_ account: String) { lock.lock(); items[account] = nil; lock.unlock() }
}

/// Minimal Keychain wrapper. Credentials never go into UserDefaults.
nonisolated struct Keychain: SecureStore {
    let service: String

    func data(for account: String) -> Data? {
        var out: CFTypeRef?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    func set(_ data: Data, for account: String) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q; add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let s = SecItemAdd(add as CFDictionary, nil)
            guard s == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(s)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func remove(_ account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

nonisolated enum PasswordHasher {
    static let rounds: UInt32 = 120_000

    static func salt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// PBKDF2-HMAC-SHA256.
    static func hash(_ password: String, salt: Data, rounds: UInt32 = rounds) -> Data {
        var derived = [UInt8](repeating: 0, count: 32)
        let pw = Array(password.utf8)
        salt.withUnsafeBytes { saltPtr in
            _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                     saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &derived, derived.count)
        }
        return Data(derived)
    }

    /// Constant-time comparison.
    static func matches(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

// MARK: - On-device implementation

/// Accounts that live only on this device, in the Keychain. Good for demos, user testing and offline use.
/// Swap in a server-backed `AuthService` to sync accounts across devices.
final class LocalAuthService: AuthService {
    private struct StoredEmailUser: Codable { var account: UserAccount; let salt: Data; let hash: Data }
    private struct Session: Codable { let userID: String; let provider: UserAccount.Provider; let key: String }

    private let keychain: SecureStore
    private(set) var currentUser: UserAccount?

    init(keychain: SecureStore = Keychain(service: "app.chestoria.accounts")) {
        self.keychain = keychain
        currentUser = restore()
    }

    private var emailUsers: [String: StoredEmailUser] { keychain.codable([String: StoredEmailUser].self, for: "email-users") ?? [:] }
    private var appleUsers: [String: UserAccount] { keychain.codable([String: UserAccount].self, for: "apple-users") ?? [:] }

    /// Writes must succeed; a silent failure would make people think they have an account when they don't.
    private func save(emailUsers users: [String: StoredEmailUser]) throws {
        do { try keychain.setCodable(users, for: "email-users") } catch { throw AuthError.storageFailed }
    }
    private func save(appleUsers users: [String: UserAccount]) throws {
        do { try keychain.setCodable(users, for: "apple-users") } catch { throw AuthError.storageFailed }
    }

    private func restore() -> UserAccount? {
        guard let s = keychain.codable(Session.self, for: "session") else { return nil }
        switch s.provider {
        case .email: return emailUsers[s.key]?.account
        case .apple: return appleUsers[s.key]
        }
    }

    private func startSession(_ user: UserAccount, key: String) throws -> UserAccount {
        do { try keychain.setCodable(Session(userID: user.id, provider: user.provider, key: key), for: "session") } catch { throw AuthError.storageFailed }
        currentUser = user
        return user
    }

    func signUp(name: String, email: String, password: String) async throws -> UserAccount {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { throw AuthError.emptyName }
        guard CredentialRules.isValidEmail(key) else { throw AuthError.invalidEmail }
        guard CredentialRules.isStrongPassword(password) else { throw AuthError.weakPassword }
        var users = emailUsers
        guard users[key] == nil else { throw AuthError.emailInUse }
        let salt = PasswordHasher.salt()
        let hash = await Task.detached(priority: .userInitiated) { PasswordHasher.hash(password, salt: salt) }.value
        let account = UserAccount(id: UUID().uuidString, displayName: name, email: key, provider: .email, createdAt: .now)
        users[key] = StoredEmailUser(account: account, salt: salt, hash: hash)
        try save(emailUsers: users)
        return try startSession(account, key: key)
    }

    func signIn(email: String, password: String) async throws -> UserAccount {
        let key = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let stored = emailUsers[key] else { throw AuthError.wrongCredentials }
        let hash = await Task.detached(priority: .userInitiated) { PasswordHasher.hash(password, salt: stored.salt) }.value
        guard PasswordHasher.matches(hash, stored.hash) else { throw AuthError.wrongCredentials }
        return try startSession(stored.account, key: key)
    }

    func signInWithApple(userID: String, name: PersonNameComponents?, email: String?, identityToken: String? = nil) async throws -> UserAccount {
        var users = appleUsers
        // Apple only shares name and email the first time; reuse what we saved after that.
        let account = users[userID] ?? UserAccount(id: UUID().uuidString,
                                                   displayName: name.map { PersonNameComponentsFormatter().string(from: $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? "Traveller",
                                                   email: email, provider: .apple, createdAt: .now)
        users[userID] = account
        try save(appleUsers: users)
        return try startSession(account, key: userID)
    }

    func updateDisplayName(_ name: String) throws -> UserAccount {
        guard var user = currentUser else { throw AuthError.notSignedIn }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AuthError.emptyName }
        user.displayName = name
        switch user.provider {
        case .email:
            var users = emailUsers
            if let key = user.email, var stored = users[key] { stored.account = user; users[key] = stored; try save(emailUsers: users) }
        case .apple:
            var users = appleUsers
            if let k = users.first(where: { $0.value.id == user.id })?.key { users[k] = user; try save(appleUsers: users) }
        }
        currentUser = user
        return user
    }

    func signOut() {
        keychain.remove("session")
        currentUser = nil
    }

    func deleteAccount() async throws {
        guard let user = currentUser else { throw AuthError.notSignedIn }
        switch user.provider {
        case .email: if let key = user.email { var u = emailUsers; u[key] = nil; try save(emailUsers: u) }
        case .apple: try save(appleUsers: appleUsers.filter { $0.value.id != user.id })
        }
        signOut()
    }
}

// MARK: - App-facing model

@Observable
final class AccountModel {
    private let service: AuthService
    private(set) var user: UserAccount?
    private(set) var isBusy = false
    var errorMessage: String?

    init(service: AuthService) {
        self.service = service
        self.user = service.currentUser
    }

    var isSignedIn: Bool { user != nil }
    /// True when accounts sync through a server (Supabase) rather than living on this device.
    var isServerBacked: Bool { service is SupabaseAuthService }

    /// The right service for this build: Supabase if configured, otherwise on-device accounts.
    static func makeDefault() -> AccountModel {
        if let config = SupabaseAuthService.Config.fromInfoPlist { return AccountModel(service: SupabaseAuthService(config: config)) }
        return AccountModel(service: LocalAuthService())
    }

    func signUp(name: String, email: String, password: String) async { await run { try await self.service.signUp(name: name, email: email, password: password) } }
    func signIn(email: String, password: String) async { await run { try await self.service.signIn(email: email, password: password) } }

    func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { errorMessage = AuthError.appleFailed.errorDescription; return }
            let token = cred.identityToken.flatMap { String(data: $0, encoding: .utf8) }
            await run { try await self.service.signInWithApple(userID: cred.user, name: cred.fullName, email: cred.email, identityToken: token) }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = AuthError.appleFailed.errorDescription
        }
    }

    func rename(_ name: String) {
        do { user = try service.updateDisplayName(name); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }

    func signOut() { service.signOut(); user = nil }

    func deleteAccount() async {
        isBusy = true; defer { isBusy = false }
        do { try await service.deleteAccount(); user = nil } catch { errorMessage = error.localizedDescription }
    }

    private func run(_ work: @escaping () async throws -> UserAccount) async {
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do { user = try await work(); Haptics.success() } catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - Settings

/// Preferences shown on the profile screen. Read anywhere with `UserDefaults.standard`.
enum Settings {
    static let haptics = "settings.haptics"
    static let recall = "settings.recall"
    static let autoRead = "settings.autoRead"
    static let storyLanguage = "settings.storyLanguage"
    static let site = "settings.site"
    static let recallHour = "settings.recallHour"
    static let recallMinute = "settings.recallMinute"

    static func register() {
        UserDefaults.standard.register(defaults: [haptics: true, recall: true, autoRead: false, storyLanguage: "en", recallHour: 8, recallMinute: 12])
    }
}
