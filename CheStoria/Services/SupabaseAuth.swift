import Foundation

/// Server-backed accounts with Supabase Auth (works with any Supabase project; no SDK needed).
/// Turned on by setting `SupabaseURL` and `SupabaseAnonKey` in Info.plist (see project.yml).
/// Accounts then sync across devices; sessions are kept in the Keychain.
///
/// Server setup (once, in the Supabase SQL editor) so people can delete their own account:
///   create function public.delete_user() returns void language sql security definer
///   as $$ delete from auth.users where id = auth.uid(); $$;
final class SupabaseAuthService: AuthService {
    struct Config: Sendable {
        let url: URL
        let anonKey: String

        static var fromInfoPlist: Config? {
            guard let u = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String, let url = URL(string: u), !u.isEmpty,
                  let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String, !key.isEmpty else { return nil }
            return Config(url: url, anonKey: key)
        }
    }

    private struct Session: Codable { let accessToken: String; let refreshToken: String; let user: UserAccount }
    private struct TokenResponse: Decodable {
        struct User: Decodable {
            let id: String
            let email: String?
            let created_at: String?
            let user_metadata: [String: String]?
            let app_metadata: [String: AnyCodableString]?
        }
        let access_token: String?
        let refresh_token: String?
        let user: User?
        // Sign-up with email confirmation returns the user object at the top level.
        let id: String?
        let email: String?
    }
    struct AnyCodableString: Decodable { let value: String?
        init(from d: Decoder) throws { value = try? d.singleValueContainer().decode(String.self) } }
    private struct ErrorResponse: Decodable { let error_code: String?; let msg: String?; let error_description: String? }

    private let config: Config
    private let store: SecureStore
    private let session: URLSession
    private(set) var currentUser: UserAccount?

    init(config: Config, store: SecureStore = Keychain(service: "app.chestoria.supabase"), session: URLSession = .shared) {
        self.config = config; self.store = store; self.session = session
        currentUser = store.codable(Session.self, for: "session")?.user
    }

    func signUp(name: String, email: String, password: String) async throws -> UserAccount {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { throw AuthError.emptyName }
        guard CredentialRules.isValidEmail(email) else { throw AuthError.invalidEmail }
        guard CredentialRules.isStrongPassword(password) else { throw AuthError.weakPassword }
        let body: [String: Any] = ["email": email, "password": password, "data": ["name": name]]
        return try await authenticate(path: "auth/v1/signup", body: body, provider: .email, fallbackName: name)
    }

    func signIn(email: String, password: String) async throws -> UserAccount {
        let body = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), "password": password]
        return try await authenticate(path: "auth/v1/token?grant_type=password", body: body, provider: .email, fallbackName: nil)
    }

    func signInWithApple(userID: String, name: PersonNameComponents?, email: String?, identityToken: String?) async throws -> UserAccount {
        guard let token = identityToken else { throw AuthError.appleFailed }
        let display = name.map { PersonNameComponentsFormatter().string(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        var user = try await authenticate(path: "auth/v1/token?grant_type=id_token", body: ["provider": "apple", "id_token": token], provider: .apple, fallbackName: display)
        if let display, user.displayName != display { user = try await rename(display) }
        return user
    }

    func updateDisplayName(_ name: String) throws -> UserAccount {
        guard var user = currentUser else { throw AuthError.notSignedIn }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AuthError.emptyName }
        user.displayName = name
        currentUser = user
        if var s = store.codable(Session.self, for: "session") { s = Session(accessToken: s.accessToken, refreshToken: s.refreshToken, user: user); try? store.setCodable(s, for: "session") }
        Task { _ = try? await rename(name) }
        return user
    }

    func signOut() {
        if let s = store.codable(Session.self, for: "session") {
            var req = request("auth/v1/logout", method: "POST"); req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
            Task { [session] in _ = try? await session.data(for: req) }
        }
        store.remove("session"); currentUser = nil
    }

    func deleteAccount() async throws {
        guard let s = store.codable(Session.self, for: "session") else { throw AuthError.notSignedIn }
        var req = request("rest/v1/rpc/delete_user", method: "POST")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data("{}".utf8)
        let (data, response) = try await session.data(for: req)
        try check(response, data)
        store.remove("session"); currentUser = nil
    }

    // MARK: - HTTP

    private func request(_ path: String, method: String) -> URLRequest {
        var req = URLRequest(url: URL(string: path, relativeTo: config.url)!)
        req.httpMethod = method
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private func authenticate(path: String, body: [String: Any], provider: UserAccount.Provider, fallbackName: String?) async throws -> UserAccount {
        var req = request(path, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        try check(response, data)
        let r = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let access = r.access_token, let refresh = r.refresh_token, let u = r.user else {
            // Project requires email confirmation: the account exists but there is no session yet.
            throw AuthError.confirmEmail
        }
        let name = u.user_metadata?["name"] ?? u.user_metadata?["full_name"] ?? fallbackName ?? u.email?.components(separatedBy: "@").first ?? "Traveller"
        let created = u.created_at.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now
        let user = UserAccount(id: u.id, displayName: name, email: u.email, provider: provider, createdAt: created)
        do { try store.setCodable(Session(accessToken: access, refreshToken: refresh, user: user), for: "session") } catch { throw AuthError.storageFailed }
        currentUser = user
        return user
    }

    @discardableResult
    private func rename(_ name: String) async throws -> UserAccount {
        guard let s = store.codable(Session.self, for: "session") else { throw AuthError.notSignedIn }
        var req = request("auth/v1/user", method: "PUT")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["name": name]])
        let (data, response) = try await session.data(for: req)
        try check(response, data)
        var user = s.user; user.displayName = name
        try? store.setCodable(Session(accessToken: s.accessToken, refreshToken: s.refreshToken, user: user), for: "session")
        currentUser = user
        return user
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AuthError.network }
        guard !(200..<300).contains(http.statusCode) else { return }
        let e = try? JSONDecoder().decode(ErrorResponse.self, from: data)
        switch (http.statusCode, e?.error_code) {
        case (_, "user_already_exists"), (_, "email_exists"): throw AuthError.emailInUse
        case (_, "weak_password"): throw AuthError.weakPassword
        case (_, "invalid_credentials"), (400, _): throw AuthError.wrongCredentials
        default: throw AuthError.network
        }
    }
}
