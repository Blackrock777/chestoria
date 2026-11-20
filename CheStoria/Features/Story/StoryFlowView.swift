import SwiftUI

/// The full-screen loop for one place: recognising → question → reveal → look closer → sticker.
struct StoryFlowView: View {
    let place: Place
    @Environment(AppModel.self) private var model
    @State private var step: Step = .recognizing
    @State private var chosen = 0

    enum Step: Int { case recognizing, question, reveal, lookCloser, sticker }

    var body: some View {
        let story = place.story!
        ZStack {
            switch step {
            case .recognizing:
                RecognizingView(place: place) { go(.question, animated: false) }
                    .transition(.opacity)
            case .question:
                QuestionView(place: place, story: story) { i in chosen = i; go(.reveal) }
                    .transition(.opacity)
            case .reveal:
                RevealView(story: story, chosen: chosen) { go(story.lookCloser == nil ? .sticker : .lookCloser) }
                    .transition(.push(from: .trailing))
            case .lookCloser:
                LookCloserView(look: story.lookCloser!) { go(.sticker) }
                    .transition(.push(from: .trailing))
            case .sticker:
                StickerEarnedView(sticker: story.sticker,
                                  onKeepExploring: { finish(.trip) },
                                  onSeeAll: { finish(.stickers) })
                    .transition(.move(edge: .bottom))
            }
        }
        .overlay(alignment: .topTrailing) {
            if step != .recognizing && step != .sticker {
                CloseButton { model.activePlace = nil }
                    .padding(.trailing, 16).padding(.top, 4)
                    .environment(\.colorScheme, .dark)
            }
        }
        #if DEBUG
        .onAppear(perform: jumpForScreenshots)
        #endif
    }

    private func go(_ next: Step, animated: Bool = true) {
        withAnimation(animated ? Motion.glide : .easeInOut(duration: 0.25)) { step = next }
    }

    private func finish(_ tab: AppTab) {
        if let story = place.story { RecallScheduler.schedule(for: place, story: story) }
        model.finishStory(at: place, goTo: tab)
    }

    #if DEBUG
    private func jumpForScreenshots() {
        switch DebugLaunch.screen {
        case "question": step = .question
        case "reveal": step = .reveal
        case "closer": step = .lookCloser
        case "sticker": step = .sticker
        default: break
        }
    }
    #endif
}

// MARK: - Recognising

/// The 1–2 second wait becomes part of the curiosity gap: brackets lock on, a scan line sweeps, clues appear.
struct RecognizingView: View {
    let place: Place
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var locked = false
    @State private var scan = false
    @State private var visibleClues = 0
    @State private var thinking = "Hmm, let me look…"
    @State private var flash = true

    var body: some View {
        GeometryReader { geo in
            let layout = CoverLayout(imageSize: UIImage.size(named: place.cameraImage), container: geo.size,
                                     anchor: CGPoint(x: place.cameraAnchor.x, y: place.cameraAnchor.y), zoom: 1.06)
            let focus = layout.rect(place.focus)
            let start = CGRect(x: (geo.size.width - 270) / 2, y: geo.size.height * 0.3, width: 270, height: 320)
            let box = locked ? focus : start

            ZStack(alignment: .topLeading) {
                CoverImage(name: place.cameraImage, anchor: place.cameraAnchor, zoom: 1.06)
                Color.black.opacity(0.32)
                Reticle(color: Palette.tufo, line: 4, corner: 30)
                    .frame(width: box.width, height: box.height)
                    .overlay(alignment: .top) {
                        Rectangle().fill(LinearGradient(colors: [.clear, Palette.tufo, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 2).shadow(color: Palette.tufo.opacity(0.7), radius: 9)
                            .padding(.horizontal, 8)
                            .offset(y: scan ? box.height * 0.92 : box.height * 0.06)
                            .opacity(locked ? 1 : 0)
                    }
                    .offset(x: box.minX, y: box.minY)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 14) {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Array((place.clues + ["✓ Got it"]).enumerated()), id: \.offset) { i, clue in
                            let got = i == place.clues.count
                            Text(clue).font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(got ? Palette.onTufo : .white)
                                .padding(.horizontal, 15).frame(height: 38)
                                .background { if got { Capsule().fill(Palette.tufo) } }
                                .glassEffect(got ? .identity : .regular, in: .capsule)
                                .opacity(i < visibleClues ? 1 : 0)
                                .scaleEffect(i < visibleClues ? 1 : 0.85)
                                .animation(Motion.pop, value: visibleClues)
                        }
                    }
                    .frame(maxWidth: 340)
                    Text(thinking).font(Typeface.hand(22)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 8)
                        .contentTransition(.opacity)
                }
                .padding(.bottom, 54)
            }
        }
        .overlay { Color.white.opacity(flash ? 1 : 0).allowsHitTesting(false) }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task {
            // Every pause checks for cancellation, so leaving the screen stops the sequence.
            func pause(_ ms: Int) async -> Bool { (try? await Task.sleep(for: .milliseconds(ms))) != nil }
            withAnimation(.easeOut(duration: 0.5)) { flash = false }
            guard await pause(250) else { return }
            withAnimation(reduce ? .default : .spring(response: 0.7, dampingFraction: 0.72)) { locked = true }
            guard await pause(450) else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatCount(3, autoreverses: true)) { scan = true }
            for i in 1...place.clues.count + 1 {
                guard await pause(reduce ? 120 : 420) else { return }
                visibleClues = i
                if i == 2 { withAnimation { thinking = place.clues.prefix(2).joined(separator: "… ").lowercased().capitalizedFirst + "…" } }
                if i == place.clues.count + 1 { withAnimation { thinking = "Got it." }; Haptics.success() }
            }
            guard await pause(700) else { return }
            onDone()
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Question

/// Ask first, tell after. The photo shrinks to the top while the sheet springs up.
struct QuestionView: View {
    let place: Place
    let story: Story
    let onAnswer: (Int) -> Void
    @State private var shown = false
    @State private var selected: Int?
    @State private var confidence = 2

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Palette.calce
                CoverImage(name: place.cameraImage, anchor: .init(x: 0.40, y: 0.62))
                    .frame(height: shown ? geo.size.height * 0.42 + geo.safeAreaInsets.top : geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
                    .animation(Motion.glide, value: shown)

                VStack(alignment: .leading, spacing: 12) {
                    Capsule().fill(Palette.hair).frame(width: 38, height: 5).frame(maxWidth: .infinity)
                    Text(story.eyebrow).font(.system(size: 12, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(Palette.stone)
                        .rise(shown, delay: 0.45)
                    Text(story.question).font(Typeface.display(31, relativeTo: .title)).foregroundStyle(Palette.piperno)
                        .fixedSize(horizontal: false, vertical: true)
                        .rise(shown, delay: 0.5)
                    Spacer(minLength: 8)
                    ForEach(Array(story.answers.enumerated()), id: \.offset) { i, a in
                        Button(a) {
                            selected = i; Haptics.tap()
                            Task { try? await Task.sleep(for: .milliseconds(480)); onAnswer(i) }
                        }
                        .buttonStyle(AnswerButtonStyle(selected: selected == i, key: ["A", "B", "C", "D"][i]))
                        .disabled(selected != nil)
                        .rise(shown, delay: 0.65 + Double(i) * 0.09, distance: 18)
                    }
                    HStack(spacing: 10) {
                        Text("How sure?").font(.system(size: 15)).foregroundStyle(Palette.stone)
                        ForEach(1...3, id: \.self) { n in
                            Button { confidence = n; Haptics.tap() } label: {
                                Circle().fill(n <= confidence ? Palette.piperno : .clear)
                                    .overlay(Circle().stroke(Palette.piperno, lineWidth: 2)).frame(width: 14, height: 14)
                                    .padding(6)
                            }
                            .accessibilityLabel(["A bit sure", "Quite sure", "Very sure"][n - 1])
                        }
                    }
                    .frame(maxWidth: .infinity).rise(shown, delay: 0.95)
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
                .frame(height: geo.size.height * 0.62 + geo.safeAreaInsets.bottom, alignment: .top)
                .background(Palette.calce, in: UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38))
                .shadow(color: .black.opacity(0.25), radius: 20, y: -6)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: shown ? 0 : geo.size.height)
                .animation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.12), value: shown)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.light)
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear { shown = true }
    }
}

// MARK: - Reveal

struct RevealView: View {
    let story: Story
    let chosen: Int
    let onNext: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var narrator = Narrator()
    @State private var wipe = false
    @State private var shown = false
    @State private var stamped = false

    private var right: Bool { chosen == story.correctIndex }
    private var reaction: String {
        right ? "Spot on! You knew it." : "You said \(story.answers[chosen].lowercased().replacingOccurrences(of: "a ", with: "", options: .anchored)). Nope! Good guess though."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(reaction).font(Typeface.hand(23)).foregroundStyle(right ? Palette.maiolica : Palette.stone)
                .mask(alignment: .leading) { Rectangle().scaleEffect(x: wipe ? 1 : 0, anchor: .leading) }
                .padding(.top, 8)
            Text(story.answerTitle).font(Typeface.display(46, relativeTo: .largeTitle)).foregroundStyle(Palette.piperno)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : -40).scaleEffect(shown ? 1 : 1.06, anchor: .leading)
                .animation(reduce ? nil : Motion.pop.delay(0.45), value: shown)
                .accessibilityAddTraits(.isHeader)
            Text(story.subtitle).font(Typeface.display(22)).foregroundStyle(Palette.azzurro).padding(.top, -6)
                .rise(shown, delay: 0.75, distance: 10)
            Text(story.body).font(.system(size: 18)).foregroundStyle(Palette.piperno).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .rise(shown, delay: 0.9)
            VerifiedPill(source: story.source).rise(shown, delay: 1.0)
            if let theory = story.theory {
                TheoryCard(theory: theory, stamped: stamped)
                    .opacity(shown ? 1 : 0).animation(.easeOut(duration: 0.4).delay(1.1), value: shown)
            }
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(Palette.tufo).frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tell it tonight").font(.system(size: 11, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(Palette.stone)
                    Text(story.dinnerLine).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.piperno)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .rise(shown, delay: 1.3)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button { narrator.toggle(story.answerTitle + " " + story.subtitle + " " + story.body) } label: {
                    Image(systemName: narrator.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.piperno)
                        .frame(width: 58, height: 58).background(Palette.sunk, in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(narrator.isSpeaking ? "Stop reading" : "Read aloud")
                Button(story.lookCloser == nil ? "Collect sticker" : "Look closer  →") { Haptics.tap(); onNext() }
                    .buttonStyle(CTAButtonStyle(kind: .tufo, shine: true))
            }
            .rise(shown, delay: 1.45)
        }
        .padding(.horizontal, 24).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.calce)
        .preferredColorScheme(.light)
        .sensoryFeedback(right ? .success : .impact(weight: .light), trigger: shown)
        .onAppear {
            shown = true
            withAnimation(reduce ? nil : .easeOut(duration: 0.9).delay(0.1)) { wipe = true }
            withAnimation(reduce ? nil : .spring(response: 0.38, dampingFraction: 0.55).delay(1.45)) { stamped = true }
            Task { try? await Task.sleep(for: .milliseconds(1700)); if story.theory != nil { Haptics.rigid() } }
        }
    }
}
