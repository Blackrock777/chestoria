import Testing
import Foundation
import UIKit
import CoreLocation
@testable import CheStoria

@MainActor
struct ContentTests {
    @Test func bundledContentIsValidInEveryLanguage() throws {
        let base = try ContentStore.loadBundled()
        let languages = base.languages(forSite: base.index.defaultSite)
        #expect(languages.count >= 5)
        for lang in languages {
            let catalog = try ContentStore.loadBundled(language: lang)
            let problems = ContentValidator.problems(in: catalog)
            #expect(problems.isEmpty, "\(lang): \(problems)")
        }
    }

    @Test func translationsChangeTextButKeepIDsAndImages() throws {
        let en = try ContentStore.loadBundled(language: "en").defaultSite
        let it = try ContentStore.loadBundled(language: "it").defaultSite
        #expect(en.places.map(\.id) == it.places.map(\.id))
        #expect(en.place(id: "thermopolium")?.story?.answerTitle != it.place(id: "thermopolium")?.story?.answerTitle)
        #expect(it.place(id: "tragic-poet")?.name == "Casa del Poeta Tragico")
        #expect(en.place(id: "thermopolium")?.cameraImage == it.place(id: "thermopolium")?.cameraImage)
        #expect(en.place(id: "thermopolium")?.story?.correctIndex == it.place(id: "thermopolium")?.story?.correctIndex)
    }

    @Test func interfaceStringsHaveEveryKeyInEveryLanguage() throws {
        let en = try ContentStore.loadBundled(language: "en").strings.table
        for lang in ["it", "fr", "de", "es"] {
            let t = try ContentStore.loadBundled(language: lang).strings.table
            #expect(Set(t.keys) == Set(en.keys), "\(lang) is missing \(Set(en.keys).subtracting(t.keys))")
        }
        let s = try ContentStore.loadBundled(language: "it").strings
        #expect(s("snap.near", "Foro") == "Vicino a te · Foro")
        #expect(s("missing.key") == "missing.key")
    }

    @Test func validatorCatchesBrokenContent() throws {
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: Bundle.main.resourceURL!.appending(path: "Content/pompeii.json"))) as! [String: Any]
        json["featuredPlace"] = "nowhere"
        var places = json["places"] as! [[String: Any]]
        places[0]["mapPoint"] = [9999, 0]
        json["places"] = places
        let site = try JSONDecoder().decode(SiteContent.self, from: JSONSerialization.data(withJSONObject: json))
        let problems = ContentValidator.problems(in: site)
        #expect(problems.contains { $0.contains("featuredPlace") })
        #expect(problems.contains { $0.contains("mapPoint") })
    }

    @Test func imageRefsAcceptAssetsAndURLs() throws {
        #expect(ImageRef("forum") == .asset("forum"))
        #expect(ImageRef("https://example.com/a.jpg") == .remote(URL(string: "https://example.com/a.jpg")!))
    }

    @Test func overlayMergesObjectsAndIdArrays() {
        let base: [String: Any] = ["a": 1, "places": [["id": "x", "name": "X", "lat": 1], ["id": "y", "name": "Y"]]]
        let overlay: [String: Any] = ["places": [["id": "y", "name": "Ypsilon"]]]
        let merged = JSONMerge.merge(base, overlay) as! [String: Any]
        let places = merged["places"] as! [[String: Any]]
        #expect(places[0]["name"] as? String == "X")
        #expect(places[1]["name"] as? String == "Ypsilon")
        #expect(merged["a"] as? Int == 1)
    }
}

struct CoverLayoutTests {
    @Test func fillsAndCentresByDefault() {
        let l = CoverLayout(imageSize: CGSize(width: 1800, height: 1200), container: CGSize(width: 393, height: 852))
        #expect(abs(l.displaySize.height - 852) < 0.001)
        #expect(abs(l.point(.init(x: 0.5, y: 0.5)).x - 196.5) < 0.001)
    }

    @Test func anchorAndZoomMoveTheTarget() {
        let l = CoverLayout(imageSize: CGSize(width: 1800, height: 1198), container: CGSize(width: 393, height: 852),
                            anchor: CGPoint(x: 0.55, y: 1), zoom: 1.15)
        let snakes = l.point(.init(x: 0.555, y: 0.72))
        #expect(snakes.y > 450 && snakes.y < 640)
        #expect(snakes.x > 150 && snakes.x < 300)
    }
}

struct HuntFeedbackTests {
    @Test func getsHotterAndFasterAsYouApproach() {
        let far = HuntFeedback(distance: 400), near = HuntFeedback(distance: 60)
        #expect(far.labelKey == "closer.colder")
        #expect(near.labelKey == "closer.hot")
        #expect(near.pulseInterval < far.pulseInterval)
        #expect(near.closeness > far.closeness)
    }

    @Test func foundInsideRadius() {
        #expect(HuntFeedback(distance: 20).isFound)
        #expect(!HuntFeedback(distance: 80).isFound)
    }
}

@MainActor
struct RecognitionTests {
    /// A crop the matcher has never seen (different framing) must still pick the right place.
    private func crop(_ name: String, _ r: CGRect) -> UIImage {
        let img = UIImage(named: name)!.normalizedCGImage!
        let rect = CGRect(x: r.minX * CGFloat(img.width), y: r.minY * CGFloat(img.height), width: r.width * CGFloat(img.width), height: r.height * CGFloat(img.height))
        return UIImage(cgImage: img.cropping(to: rect)!)
    }

    @Test func eachPlaceIsRecognisedFromItsOwnPhoto() async throws {
        let catalog = try ContentStore.loadBundled()
        let site = catalog.site(id: "pompeii")!
        let matcher = PlaceMatcher()
        #expect(matcher.usesAI, "SigLIP model should load from the app bundle")
        let cases: [(String, CGRect, String)] = [
            ("thermo", CGRect(x: 0.1, y: 0.15, width: 0.75, height: 0.8), "thermopolium"),
            ("shrine", CGRect(x: 0.15, y: 0.1, width: 0.7, height: 0.75), "thermopolium"),
            ("caveCanem", CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), "tragic-poet"),
            ("forum", CGRect(x: 0.05, y: 0.05, width: 0.85, height: 0.85), "forum"),
        ]
        for (asset, rect, expected) in cases {
            let result = await matcher.identify(crop(asset, rect), in: site, near: nil, catalog: catalog)
            if case .confident(let p) = result { #expect(p.id == expected, "\(asset) → \(p.id)") }
            else { Issue.record("\(asset) not confident: \(result)") }
        }
    }

    private func fixture(_ name: String) throws -> UIImage {
        let url = try #require(Bundle(for: FixtureMarker.self).url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures"))
        return try #require(UIImage(contentsOfFile: url.path))
    }

    /// Photos that are NOT reference images: a different shot of the same place must not pick the wrong place,
    /// and a photo of somewhere else must not be confidently matched.
    @Test func unseenPhotosAreHandledSafely() async throws {
        let catalog = try ContentStore.loadBundled()
        let site = catalog.site(id: "pompeii")!
        let matcher = PlaceMatcher()

        if case .confident(let p) = await matcher.identify(try fixture("cave-canem-other"), in: site, near: nil, catalog: catalog) {
            #expect(p.id == "tragic-poet")
        } else { Issue.record("second Cave canem photo should be recognised") }

        switch await matcher.identify(try fixture("forum-tour-group"), in: site, near: nil, catalog: catalog) {
        case .confident(let p): #expect(p.id == "forum")
        case .unsure(let ps, _): #expect(ps.first?.id == "forum")
        case .notAPlace: Issue.record("forum photo should at least be offered first")
        }

        if case .confident(let p) = await matcher.identify(try fixture("street-negative"), in: site, near: nil, catalog: catalog) {
            Issue.record("an unrelated street was confidently matched to \(p.id)")
        }
    }

    /// Everyday photos: not a place, and the AI says what it is (in the chosen language).
    @Test func everydayPhotosAreNamedNotMatched() async throws {
        let catalog = try ContentStore.loadBundled(language: "en")
        let site = catalog.site(id: "pompeii")!
        let matcher = PlaceMatcher()
        for (name, expected) in [("coffee-negative", "a cup of coffee"), ("laptop-negative", "a laptop")] {
            if case .notAPlace(let label, let heritage, _) = await matcher.identify(try fixture(name), in: site, near: nil, catalog: catalog) {
                #expect(label == expected && !heritage, "\(name) → \(label ?? "-")")
            } else { Issue.record("\(name) should not be a place") }
        }
        let it = try ContentStore.loadBundled(language: "it")
        if case .notAPlace(let label, _, _) = await matcher.identify(try fixture("coffee-negative"), in: site, near: nil, catalog: it) {
            #expect(label == "una tazza di caffè")
        }
    }

    @Test func vocabularyLoadsFromContent() throws {
        let v = try #require(try ContentStore.loadBundled().vocabulary)
        #expect(v.model == "google/siglip-base-patch16-224")
        #expect(v.labels.count >= 50 && v.labels.allSatisfy { $0.embedding.count == 768 })
        #expect(v.placeText["thermopolium"]?.count == 2)
    }

    @Test func farAwayLocationDoesNotFilterCandidates() throws {
        let site = try ContentStore.loadBundled().defaultSite
        let london = CLLocation(latitude: 51.5, longitude: -0.12)
        #expect(RecognitionPolicy.candidates(site.storyPlaces, near: london).count == site.storyPlaces.count)
        let atThermo = CLLocation(latitude: 40.7497, longitude: 14.4890)
        #expect(RecognitionPolicy.candidates(site.storyPlaces, near: atThermo).contains { $0.id == "thermopolium" })
    }
}

@MainActor
struct AppModelTests {
    private func freshModel() throws -> AppModel {
        let defaults = UserDefaults(suiteName: "chestoria.tests.\(UUID().uuidString)")!
        return AppModel(catalog: try ContentStore.loadBundled(), defaults: defaults, loader: { try? ContentStore.loadBundled(language: $0) })
    }

    @Test func newTripStartsEmptyAndWelcomeIsReal() throws {
        let m = try freshModel()
        #expect(m.visitedPlaces.isEmpty && m.collectedStickers.isEmpty)
        #expect(m.welcomeEyebrow == "Welcome to Pompeii")
        m.finishStory(at: m.site.place(id: "forum")!, goTo: .trip)
        #expect(m.welcomeEyebrow == "Pompeii · Day 1 of your trip")
    }

    @Test func demoTripComesFromContent() throws {
        let m = try freshModel()
        m.loadDemo()
        #expect(m.visitedPlaces.map(\.id) == ["forum", "tragic-poet"])
        #expect(Set(m.collectedStickers.map(\.sticker.id)) == ["vesuvius-view", "cave-canem"])
    }

    @Test func finishingAStoryCollectsItsStickerOnce() throws {
        let m = try freshModel()
        let thermo = try #require(m.site.place(id: "thermopolium"))
        m.startStory(at: thermo)
        #expect(m.activeFlow?.suggested == thermo)
        m.finishStory(at: thermo, goTo: .trip)
        m.finishStory(at: thermo, goTo: .trip)
        #expect(m.collectedStickers.filter { $0.sticker.id == "guardian-snakes" }.count == 1)
        #expect(m.visitedPlaces.last?.id == "thermopolium")
        #expect(m.activeFlow == nil && m.selectedTab == .trip)
    }

    @Test func switchingLanguageKeepsProgress() throws {
        let m = try freshModel()
        m.loadDemo()
        m.setLanguage("de")
        #expect(m.language == "de")
        #expect(m.site.place(id: "tragic-poet")?.name == "Haus des tragischen Dichters")
        #expect(m.collectedStickers.count == 2)
        #expect(m.strings("tab.trip") == "Meine Reise")
    }
}

@MainActor
struct AuthTests {
    private func service() -> LocalAuthService {
        LocalAuthService(keychain: InMemorySecureStore())
    }

    @Test func signUpSignOutSignIn() async throws {
        let s = service()
        let user = try await s.signUp(name: "Pooja", email: "Pooja@Example.com", password: "pompeii79")
        #expect(user.email == "pooja@example.com" && s.currentUser == user)
        s.signOut()
        #expect(s.currentUser == nil)
        let again = try await s.signIn(email: "pooja@example.com", password: "pompeii79")
        #expect(again.id == user.id)
    }

    @Test func rejectsBadInputAndWrongPassword() async throws {
        let s = service()
        await #expect(throws: AuthError.invalidEmail) { try await s.signUp(name: "A", email: "nope", password: "pompeii79") }
        await #expect(throws: AuthError.weakPassword) { try await s.signUp(name: "A", email: "a@b.co", password: "short") }
        _ = try await s.signUp(name: "A", email: "a@b.co", password: "pompeii79")
        await #expect(throws: AuthError.emailInUse) { try await s.signUp(name: "B", email: "A@B.CO", password: "pompeii79") }
        s.signOut()
        await #expect(throws: AuthError.wrongCredentials) { try await s.signIn(email: "a@b.co", password: "wrongpass1") }
    }

    @Test func appleSignInRemembersNameAndDeleteRemovesAccount() async throws {
        let s = service()
        var name = PersonNameComponents(); name.givenName = "Pooja"; name.familyName = "T"
        let first = try await s.signInWithApple(userID: "apple.123", name: name, email: "p@privaterelay.appleid.com", identityToken: nil)
        s.signOut()
        let second = try await s.signInWithApple(userID: "apple.123", name: nil, email: nil, identityToken: nil)
        #expect(second.id == first.id && second.displayName == "Pooja T")
        try await s.deleteAccount()
        #expect(s.currentUser == nil)
        let third = try await s.signInWithApple(userID: "apple.123", name: nil, email: nil, identityToken: nil)
        #expect(third.id != first.id)
    }

    @Test func passwordsAreSaltedAndCheckedInConstantTime() {
        let a = PasswordHasher.hash("pompeii79", salt: Data([1, 2, 3]), rounds: 1000)
        let b = PasswordHasher.hash("pompeii79", salt: Data([1, 2, 4]), rounds: 1000)
        #expect(a != b)
        #expect(PasswordHasher.matches(a, a) && !PasswordHasher.matches(a, b))
    }
}


final class FixtureMarker {}


@MainActor
struct LocationStatusTests {
    @Test func neverInventsADistance() throws {
        let site = try ContentStore.loadBundled().site(id: "pompeii")!
        #expect(LocationStatus.compute(site: site, location: nil, authorization: .authorizedWhenInUse) == .locating)
        #expect(LocationStatus.compute(site: site, location: nil, authorization: .denied) == .off)
        let atThermo = CLLocation(latitude: 40.7497, longitude: 14.4892)
        if case .near(let p, let m) = LocationStatus.compute(site: site, location: atThermo, authorization: .authorizedWhenInUse) {
            #expect(p.id == "thermopolium" && m < 30)
        } else { Issue.record("expected near") }
        let london = CLLocation(latitude: 51.5072, longitude: -0.1276)
        if case .far(let name, let distance) = LocationStatus.compute(site: site, location: london, authorization: .authorizedWhenInUse) {
            #expect(name == "Pompeii")
            #expect(distance.contains("1") && !distance.contains("12 m"))
        } else { Issue.record("expected far") }
    }
}

@MainActor
struct SiteTests {
    private func freshModel() throws -> (AppModel, UserDefaults) {
        let defaults = UserDefaults(suiteName: "chestoria.tests.\(UUID().uuidString)")!
        return (AppModel(catalog: try ContentStore.loadBundled(), defaults: defaults, loader: { try? ContentStore.loadBundled(language: $0) }), defaults)
    }

    @Test func naplesIsASecondSiteWithItsOwnTrip() throws {
        let (m, defaults) = try freshModel()
        #expect(m.catalog.sites.map(\.id) == ["pompeii", "naples"])
        m.switchSite(to: "naples")
        #expect(m.site.city == "Naples" && m.visitedPlaces.isEmpty)
        let gesu = try #require(m.site.place(id: "gesu-nuovo"))
        m.finishStory(at: gesu, goTo: .trip)
        m.switchSite(to: "pompeii")
        #expect(m.collectedStickers.isEmpty)
        m.switchSite(to: "naples")
        #expect(m.collectedStickers.map(\.sticker.id) == ["spiky-palace"])
        let reopened = AppModel(catalog: try ContentStore.loadBundled(), defaults: defaults, loader: { _ in nil })
        #expect(reopened.site.id == "naples")
    }

    @Test func everyStoryHasSources() throws {
        for site in try ContentStore.loadBundled().sites {
            for p in site.storyPlaces { #expect((p.story?.factCheck?.sources.count ?? 0) >= 1, "\(p.id) has no sources") }
        }
    }

    @Test func recallAnswersAreCounted() throws {
        let (m, _) = try freshModel()
        m.recordRecall(correct: true); m.recordRecall(correct: false)
        #expect(m.recallStats.remembered == 1 && m.recallStats.answered == 2)
    }

    @Test func naplesPlacesAreRecognisedFromTheirPhotos() async throws {
        let catalog = try ContentStore.loadBundled()
        let site = catalog.site(id: "naples")!
        let matcher = PlaceMatcher()
        for (asset, expected) in [("gesuFacade2", "gesu-nuovo"), ("castelOvo", "castel-ovo"), ("veiledChristFace", "sansevero"), ("plebiscitoVesuvius", "plebiscito")] {
            let img = UIImage(named: asset)!.normalizedCGImage!
            let crop = UIImage(cgImage: img.cropping(to: CGRect(x: img.width / 12, y: img.height / 12, width: img.width * 5 / 6, height: img.height * 5 / 6))!)
            switch await matcher.identify(crop, in: site, near: nil, catalog: catalog) {
            case .confident(let p): #expect(p.id == expected, "\(asset) → \(p.id)")
            case .unsure(let ps, _): #expect(ps.first?.id == expected, "\(asset) unsure, first \(ps.first?.id ?? "-")")
            case .notAPlace: Issue.record("\(asset) matched nothing")
            }
        }
    }
}

nonisolated final class Stub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var lastBody: [String: Any]?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open(); var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            stream.close(); Stub.lastBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        let (status, body) = Stub.handler?(request) ?? (500, "{}")
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}


/// Supabase requests and responses, against a stubbed server.
@MainActor
struct SupabaseAuthTests {
    private func service() -> SupabaseAuthService {
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [Stub.self]
        return SupabaseAuthService(config: .init(url: URL(string: "https://demo.supabase.co/")!, anonKey: "anon"), store: InMemorySecureStore(), session: URLSession(configuration: cfg))
    }

    @Test func signInStoresSessionAndUser() async throws {
        Stub.handler = { req in
            #expect(req.url?.absoluteString == "https://demo.supabase.co/auth/v1/token?grant_type=password")
            #expect(req.value(forHTTPHeaderField: "apikey") == "anon")
            return (200, #"{"access_token":"a","refresh_token":"r","user":{"id":"u1","email":"p@x.co","created_at":"2026-11-20T10:00:00Z","user_metadata":{"name":"Pooja"}}}"#)
        }
        let s = service()
        let user = try await s.signIn(email: "P@X.co", password: "pompeii79")
        #expect(user.id == "u1" && user.displayName == "Pooja" && s.currentUser == user)
        #expect(Stub.lastBody?["email"] as? String == "p@x.co")
    }

    @Test func mapsServerErrors() async throws {
        let s = service()
        Stub.handler = { _ in (400, #"{"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#) }
        await #expect(throws: AuthError.wrongCredentials) { try await s.signIn(email: "p@x.co", password: "nope12345") }
        Stub.handler = { _ in (422, #"{"error_code":"user_already_exists"}"#) }
        await #expect(throws: AuthError.emailInUse) { try await s.signUp(name: "P", email: "p@x.co", password: "pompeii79") }
        Stub.handler = { _ in (200, #"{"id":"u2","email":"new@x.co"}"#) }
        await #expect(throws: AuthError.confirmEmail) { try await s.signUp(name: "N", email: "new@x.co", password: "pompeii79") }
    }
}
