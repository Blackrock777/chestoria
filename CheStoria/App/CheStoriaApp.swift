import SwiftUI

@main
struct CheStoriaApp: App {
    @State private var model: AppModel
    @State private var recognizer: PlaceRecognizer

    init() {
        let content: ContentBundle
        do { content = try ContentStore.load() } catch { fatalError("Bundled pompeii.json is missing or invalid: \(error)") }
        let model = AppModel(content: content)
        #if DEBUG
        DebugLaunch.apply(to: model)
        #endif
        _model = State(initialValue: model)
        _recognizer = State(initialValue: PlaceRecognizer(places: content.places))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(recognizer)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.hasOnboarded {
                MainTabs()
                    .transition(.opacity)
            } else {
                WelcomeView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: model.hasOnboarded)
        .fullScreenCover(item: $model.activePlace) { place in
            StoryFlowView(place: place)
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Snap", systemImage: "camera", value: AppTab.snap) { SnapView() }
            Tab("My trip", systemImage: "map", value: AppTab.trip) { TripView() }
            Tab("Stickers", systemImage: "seal", value: AppTab.stickers) { StickersView() }
        }
        .tint(model.selectedTab == .snap ? Palette.tufo : Palette.azzurro)
    }
}

#if DEBUG
/// Launch arguments for screenshots and demos, e.g. `-screen reveal` or `-reset`.
enum DebugLaunch {
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static var autoSolve: Bool { ProcessInfo.processInfo.arguments.contains("-autosolve") }

    static func apply(to model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-reset") { model.resetDemo() }
        guard let s = screen else { return }
        if s != "welcome" { model.completeOnboarding() }
        switch s {
        case "trip": model.selectedTab = .trip
        case "stickers": model.selectedTab = .stickers
        case "recognizing", "question", "reveal", "closer", "sticker":
            if let p = model.content.place(id: "thermopolium") { model.startStory(at: p) }
        default: break
        }
    }
}
#endif
