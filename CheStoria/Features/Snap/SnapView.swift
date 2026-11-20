import SwiftUI

/// Home: full-screen camera, one yellow shutter. GPS already knows the place.
struct SnapView: View {
    @Environment(AppModel.self) private var model
    @Environment(PlaceRecognizer.self) private var recognizer
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var camera = CameraSession()
    @State private var flash = 0
    @State private var shown = false

    var body: some View {
        let nearest = recognizer.nearest
        ZStack {
            CameraBackground(camera: camera, place: nearest.place, drifting: !reduce)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                GlassChip {
                    LiveDot()
                    Text("Near you · \(nearest.place.name)")
                    if let m = nearest.meters { Text("· \(m) m").font(.system(size: 13)).opacity(0.75) }
                }
                .padding(.top, 8)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : -14).scaleEffect(shown ? 1 : 0.9)
                .animation(Motion.pop.delay(0.15), value: shown)

                Spacer()
                BreathingReticle().frame(width: 270, height: 320)
                    .opacity(shown ? 1 : 0).scaleEffect(shown ? 1 : 1.15)
                    .animation(Motion.glide.delay(0.25), value: shown)
                Spacer()

                Text("Point at anything that makes you curious")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                    .padding(.bottom, 18)
                ShutterButton {
                    Haptics.tap(); flash += 1
                    Task { try? await Task.sleep(for: .milliseconds(150)); model.startStory(at: nearest.place) }
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
    }
}

extension SnapView {
    static var isScreenshotRun: Bool {
        #if DEBUG
        return DebugLaunch.screen != nil
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
    var frozen = false

    var body: some View {
        if CameraSession.isAvailable && !frozen {
            CameraPreview(session: camera.session)
        } else {
            CoverImage(name: place.cameraImage, anchor: place.cameraAnchor)
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
