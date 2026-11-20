import SwiftUI

@main
struct CheStoriaApp: App {
    @State private var model: AppModel
    @State private var recognizer = PlaceRecognizer()
    @State private var matcher = PlaceMatcher()
    @State private var account = AccountModel(service: LocalAuthService())

    init() {
        Settings.register()
        let catalog: Catalog
        do {
            let languages = try ContentStore.loadBundled().index.sites.flatMap(\.languages)
            catalog = try ContentStore.load(language: AppModel.preferredLanguage(available: Array(Set(languages))))
        } catch {
            fatalError("Bundled content is missing or invalid: \(error)")
        }
        let model = AppModel(catalog: catalog)
        #if DEBUG
        DebugLaunch.apply(to: model)
        #endif
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(recognizer)
                .environment(matcher)
                .environment(account)
                .task {
                    // New content from the server is validated, cached and used on the next launch.
                    if let url = ContentStore.remoteBaseURL { try? await ContentStore.refresh(from: url) }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.hasOnboarded { MainTabs().transition(.opacity) } else { WelcomeView().transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.4), value: model.hasOnboarded)
        .fullScreenCover(item: $model.activeFlow) { request in StoryFlowView(request: request) }
        .sheet(isPresented: $model.showProfile) { ProfileView() }
        .sheet(isPresented: $model.showLanguagePicker) { LanguagePicker() }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let t = model.strings
        TabView(selection: $model.selectedTab) {
            Tab(t("tab.snap"), systemImage: "camera", value: AppTab.snap) { SnapView() }
            Tab(t("tab.trip"), systemImage: "map", value: AppTab.trip) { TripView() }
            Tab(t("tab.stickers"), systemImage: "seal", value: AppTab.stickers) { StickersView() }
        }
        .tint(model.selectedTab == .snap ? Palette.tufo : Palette.azzurro)
    }
}

#if DEBUG
/// Launch arguments for screenshots and demos:
/// `-reset`, `-lang it`, `-screen reveal`, `-autosolve`, `-capture caveCanem` (runs real recognition on an asset).
enum DebugLaunch {
    private static func value(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static var screen: String? { value("-screen") }
    static var autoSolve: Bool { ProcessInfo.processInfo.arguments.contains("-autosolve") }

    static func apply(to model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-reset") { model.resetDemo() }
        if let lang = value("-lang") { model.setLanguage(lang) }
        if let asset = value("-capture"), let photo = UIImage(named: asset), let fallback = model.site.featured {
            model.completeOnboarding(); model.startStory(at: fallback, photo: photo); return
        }
        guard let s = screen else { return }
        if s != "welcome" { model.completeOnboarding() } else { model.resetOnboarding() }
        switch s {
        case "trip": model.selectedTab = .trip
        case "stickers": model.selectedTab = .stickers
        case "profile": model.showProfile = true
        case "language": model.showLanguagePicker = true
        case "recognizing", "question", "reveal", "closer", "sticker":
            if let p = model.site.featured { model.startStory(at: p) }
        default: break
        }
    }
}
#endif
