import PhotosUI
import SwiftUI

/// Home: full-screen camera, one yellow shutter. Location narrows it down; the photo decides.
struct SnapView: View {
    @Environment(AppModel.self) private var model
    @Environment(PlaceRecognizer.self) private var recognizer
    @Environment(PlaceMatcher.self) private var matcher
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var camera = CameraSession()
    @State private var flash = 0
    @State private var shown = false
    @State private var picked: PhotosPickerItem?

    var body: some View {
        let t = model.strings
        let status = recognizer.status(in: model.site, locale: Locale(identifier: model.language))
        let fallback = recognizer.fallbackPlace(in: model.site)
        ZStack {
            CameraBackground(camera: camera, place: fallback, drifting: !reduce)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    ProfileButton(style: .glass)
                    Spacer()
                    LocationChip(status: status)
                    Spacer()
                    Color.clear.frame(width: 8, height: 44)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : -14)
                .animation(Motion.pop.delay(0.15), value: shown)

                if let other = recognizer.siteNearby(in: model.catalog, current: model.site) {
                    Button { Haptics.tap(); withAnimation { model.switchSite(to: other.id) } } label: {
                        Label(t("site.switchTo", other.city), systemImage: "arrow.triangle.swap")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.onTufo)
                            .padding(.horizontal, 14).frame(height: 36).background(Palette.tufo, in: .capsule)
                    }
                    .padding(.top, 10).transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
                BreathingReticle().frame(width: 270, height: 320)
                    .opacity(shown ? 1 : 0).scaleEffect(shown ? 1 : 1.15)
                    .animation(Motion.glide.delay(0.25), value: shown)
                Spacer()

                Text(t("snap.hint"))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                    .padding(.bottom, 18)
                ZStack {
                    ShutterButton(label: t("snap.takePhoto")) { snap(fallback: fallback) }
                    HStack {
                        PhotosPicker(selection: $picked, matching: .images) {
                            Image(systemName: "photo.on.rectangle").font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white).frame(width: 52, height: 52)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(t("snap.pickPhoto"))
                        Spacer()
                    }
                    .padding(.horizontal, 36)
                }
                .scaleEffect(shown ? 1 : 0.6).opacity(shown ? 1 : 0)
                .animation(Motion.pop.delay(0.35), value: shown)
                .padding(.bottom, 24)
            }
            FlashOverlay(trigger: flash)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            shown = true
            if !Self.isScreenshotRun { recognizer.start() }
            if CameraSession.isAvailable { camera.start() }
        }
        .onDisappear { camera.stop() }
        .onChange(of: recognizer.lastLocation) { updateLiveActivity() }
        .onChange(of: model.activeFlow == nil) { _, idle in if !idle { LiveActivityController.shared.end() } }
        .task(id: model.site.id) { await matcher.prepare(site: model.site) }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    model.startStory(at: fallback, photo: image)
                }
                picked = nil
            }
        }
    }

    private func updateLiveActivity() {
        LiveActivityController.shared.update(status: recognizer.status(in: model.site), site: model.site,
                                             visited: Set(model.visitedPlaces.map(\.id)), strings: model.strings)
    }

    private func snap(fallback: Place) {
        Haptics.tap(); flash += 1
        Task {
            let photo = await camera.capture()
            try? await Task.sleep(for: .milliseconds(120))
            model.startStory(at: fallback, photo: photo)
        }
    }
}

/// Tells the truth about location: off, locating, at the site, or far away.
private struct LocationChip: View {
    let status: LocationStatus
    @Environment(AppModel.self) private var model

    var body: some View {
        let t = model.strings
        Button(action: tap) {
            HStack(spacing: 10) {
                switch status {
                case .near(let place, let meters):
                    LiveDot()
                    Text(t("snap.near", place.name)).lineLimit(1).minimumScaleFactor(0.75)
                    Text("· \(meters) m").font(.system(size: 13)).opacity(0.75).fixedSize()
                case .locating:
                    ProgressView().controlSize(.mini).tint(.white)
                    Text(t("snap.locating")).lineLimit(1).minimumScaleFactor(0.75)
                case .far(let site, let distance):
                    Image(systemName: "location.fill").font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t("snap.far", site, distance)).lineLimit(1).minimumScaleFactor(0.75)
                        Text(t("snap.anyPhoto")).font(.system(size: 11)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.7)
                    }
                case .off:
                    Image(systemName: "location.slash.fill").font(.system(size: 12))
                    Text(t("snap.locationOff")).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).frame(minHeight: 44)
        }
        .glassEffect(.regular, in: .capsule)
        .disabled(status != .off)
        .animation(.easeInOut, value: status)
    }

    private func tap() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

extension SnapView {
    static var isScreenshotRun: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-noLocation")
        #else
        return false
        #endif
    }
}

/// Live camera on a device; in the simulator, the place's photo with a gentle hand-held drift.
struct CameraBackground: View {
    let camera: CameraSession
    let place: Place
    var drifting = true

    var body: some View {
        if CameraSession.isAvailable {
            CameraPreview(session: camera.session)
        } else {
            CoverImage(place.cameraImage, anchor: place.cameraAnchor)
                .phaseAnimator([0, 1, 2], trigger: drifting) { view, phase in
                    view.scaleEffect(drifting ? [1.06, 1.07, 1.06][phase] : 1.06)
                        .offset(x: drifting ? [0, -5, 4][phase] : 0, y: drifting ? [0, 4, -3][phase] : 0)
                        .rotationEffect(.degrees(drifting ? [0, -0.3, 0.25][phase] : 0))
                } animation: { _ in .easeInOut(duration: 3.5) }
        }
    }
}

private struct BreathingReticle: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var breathe = false
    var body: some View {
        Reticle()
            .scaleEffect(breathe ? 0.965 : 1)
            .onAppear { guard !reduce else { return }; withAnimation(.easeInOut(duration: 1.2).repeatForever()) { breathe = true } }
            .accessibilityHidden(true)
    }
}
