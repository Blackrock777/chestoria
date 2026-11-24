import AVFoundation
import PhotosUI
import SwiftUI

/// Home: full-screen camera, one yellow shutter. Location narrows it down; the photo decides.
struct SnapView: View {
    @Environment(AppModel.self) private var model
    @Environment(PlaceRecognizer.self) private var recognizer
    @Environment(PlaceMatcher.self) private var matcher
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = CameraSession()
    @State private var flash = 0
    @State private var shown = false
    @State private var picked: PhotosPickerItem?
    @State private var nearby: NearbyPick?
    @State private var cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isCapturing = false
    @State private var showCaptureError = false
    @State private var zoom: CGFloat = 1
    @GestureState private var zoomStart: CGFloat?

    var body: some View {
        let t = model.strings
        let status = recognizer.status(in: model.site, locale: Locale(identifier: model.language))
        let fallback = recognizer.fallbackPlace(in: model.site)
        ZStack {
            CameraBackground(camera: camera, place: fallback, live: canUseCamera, drifting: !reduce)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            if canUseCamera {
                Color.clear.contentShape(.rect)
                    .gesture(MagnifyGesture()
                        .updating($zoomStart) { _, start, _ in if start == nil { start = zoom } }
                        .onChanged { value in zoom = min(3, max(1, (zoomStart ?? zoom) * value.magnification)) })
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                HStack {
                    ProfileButton(style: .glass)
                    Spacer()
                    LocationChip(status: status) { place, meters in nearby = NearbyPick(place: place, meters: meters) }
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

                LiveGuessChip(guess: canUseCamera ? matcher.live : nil, hint: t(canUseCamera ? "snap.hint" : "snap.noCameraHint"))
                    .padding(.bottom, 14)
                if canUseCamera { zoomControls }
                ZStack {
                    ShutterButton(label: t(canUseCamera ? "snap.takePhoto" : "snap.enableCamera")) {
                        if canUseCamera { snap(fallback: fallback) } else { enableCamera() }
                    }
                    .disabled(isCapturing || !CameraSession.isAvailable)
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
            refreshCamera()
        }
        .onDisappear { camera.stop() }
        .onChange(of: zoom) { _, factor in
            matcher.clearLive()
            camera.zoom(to: factor)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshCamera() } else { camera.stop() }
        }
        .alert(t("snap.captureFailed"), isPresented: $showCaptureError) {
            Button(t("common.done"), role: .cancel) {}
        }
        #if DEBUG
        .task { if DebugLaunch.screen == "nearby" { nearby = NearbyPick(place: fallback, meters: 40) } }
        #endif
        .sheet(item: $nearby) { pick in
            NearbyPlaceCard(place: pick.place, meters: pick.meters) {
                nearby = nil
                model.startStory(at: pick.place)
            }
        }
        .onChange(of: recognizer.lastLocation, initial: true) { updateLiveActivity() }
        .onChange(of: recognizer.authorization) { updateLiveActivity() }
        .onChange(of: model.site.id) { updateLiveActivity() }
        .onChange(of: model.language) { updateLiveActivity() }
        .onChange(of: model.state.visited) { updateLiveActivity() }
        .onChange(of: model.activeFlow == nil) { updateLiveActivity() }
        .task(id: model.site.id + model.language) {
            matcher.clearLive()
            await matcher.prepare(site: model.site)
            if CameraSession.isAvailable {
                // Real camera: a frame about twice a second goes to the on-device AI.
                camera.onFrame = { [matcher, model] buffer in
                    nonisolated(unsafe) let frame = buffer
                    Task { @MainActor in matcher.liveGuess(buffer: frame, site: model.site, catalog: model.catalog) }
                }
            } else if let cg = ImageLoader.shared.cached(fallback.cameraImage)?.normalizedCGImage {
                // Simulator: the stand-in photo is what the "camera" sees.
                matcher.liveGuess(image: cg, site: model.site, catalog: model.catalog)
            }
        }
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

    private var zoomControls: some View {
        let zoomValue = Double(zoom).formatted(.number.precision(.fractionLength(0...1)))
        return HStack(spacing: 6) {
            ForEach([1, 2, 3], id: \.self) { factor in
                let selected = abs(zoom - CGFloat(factor)) < 0.05
                Button {
                    zoom = CGFloat(factor)
                } label: {
                    Text("\(factor)×")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 44, height: 44)
                        .foregroundStyle(selected ? Palette.tufo : Color.white)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.strings("snap.zoom"))
        .accessibilityValue(Text("\(zoomValue)×"))
        .padding(.bottom, 12)
    }

    private func updateLiveActivity() {
        guard model.activeFlow == nil else { LiveActivityController.shared.end(); return }
        LiveActivityController.shared.update(fix: recognizer.lastLocation, authorization: recognizer.authorization,
                                             site: model.site, visited: Set(model.state.visited), strings: model.strings)
    }

    private func snap(fallback: Place) {
        guard !isCapturing else { return }
        isCapturing = true
        Haptics.tap()
        Task {
            defer { isCapturing = false }
            guard let photo = await camera.capture() else {
                showCaptureError = true
                return
            }
            if !reduce { flash += 1 }
            model.startStory(at: fallback, photo: photo)
        }
    }

    private var canUseCamera: Bool {
        CameraSession.isAvailable && cameraAccess == .authorized
    }

    private func refreshCamera() {
        cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
        if canUseCamera && scenePhase == .active {
            camera.start()
            camera.zoom(to: zoom)
        }
    }

    private func enableCamera() {
        if cameraAccess == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                refreshCamera()
            }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// Real-time AI: what the camera sees right now, and whether it's one of our places.
private struct LiveGuessChip: View {
    let guess: LiveGuess?
    let hint: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let t = model.strings
        Group {
            if let place = guess?.place {
                Label(t("ai.livePlace", place.name), systemImage: "sparkles")
                    .foregroundStyle(Palette.onTufo).padding(.horizontal, 14).frame(height: 36).background(Palette.tufo, in: .capsule)
            } else if let label = guess?.label {
                Label(t("ai.liveSee", label), systemImage: "eye")
                    .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 36).glassEffect(.regular, in: .capsule)
            } else {
                Text(hint).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 8)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .lineLimit(1).minimumScaleFactor(0.75)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: guess)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Tells the truth about location: off, locating, at the site, or far away.
private struct LocationChip: View {
    let status: LocationStatus
    var onNear: (Place, Int) -> Void = { _, _ in }
    @Environment(AppModel.self) private var model
    @Environment(PlaceRecognizer.self) private var recognizer

    var body: some View {
        let t = model.strings
        Button(action: tap) {
            HStack(spacing: 10) {
                switch status {
                case .near(let place, let meters):
                    LiveDot()
                    Text(t("snap.near", place.name)).lineLimit(1).minimumScaleFactor(0.75)
                    Text("· \(meters) m").font(.system(size: 13)).opacity(0.75).fixedSize()
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).opacity(0.75)
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
        .disabled(!isTappable)
        .animation(.easeInOut, value: status)
    }

    private var isTappable: Bool {
        switch status { case .near, .off: true; default: false }
    }

    private func tap() {
        if case .near(let place, let meters) = status { Haptics.tap(); onNear(place, meters); return }
        if recognizer.authorization == .notDetermined {
            recognizer.requestPermission()
            return
        }
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
    var live = CameraSession.isAvailable
    var drifting = true

    var body: some View {
        if live {
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

private struct NearbyPick: Identifiable {
    let place: Place
    let meters: Int
    var id: String { place.id }
}

/// Tapping "Near you": the place, a photo, and one clear invitation to hear its story.
private struct NearbyPlaceCard: View {
    let place: Place
    let meters: Int
    let onStart: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = model.strings
        let p = model.site.place(id: place.id) ?? place
        VStack(alignment: .leading, spacing: 16) {
            PlaceGallery(place: p, topInset: 12)
                .frame(height: 230)
                .clipShape(.rect(cornerRadius: 24))
            VStack(alignment: .leading, spacing: 4) {
                Label(t("snap.nearLabel", "\(meters)"), systemImage: "location.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.azzurro)
                Text(p.name).font(Typeface.display(28, relativeTo: .title)).foregroundStyle(Palette.piperno)
                Text(p.street).font(.subheadline).foregroundStyle(.secondary)
            }
            if let story = p.story {
                Text(story.question).font(.body).foregroundStyle(Palette.piperno).fixedSize(horizontal: false, vertical: true)
                Button(t("snap.nearStart")) { Haptics.tap(); onStart() }
                    .buttonStyle(CTAButtonStyle(kind: .tufo, shine: true))
            } else {
                Label(t("place.comingSoon"), systemImage: "hourglass").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.calce)
    }
}
