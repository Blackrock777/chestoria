import SwiftUI

/// The full-screen loop: recognising → (choose) → question → reveal → look closer → sticker.
struct StoryFlowView: View {
    let request: FlowRequest
    @Environment(AppModel.self) private var model
    @State private var place: Place?
    @State private var choices: [Place] = []
    @State private var noMatch = false
    @State private var step: Step = .recognizing
    @State private var chosen = 0

    enum Step: Int { case recognizing, choose, question, reveal, lookCloser, sticker }

    /// Re-read the place from the current site, so a language change mid-flow shows translated text.
    private var current: Place? { place.flatMap { model.site.place(id: $0.id) } ?? place }

    var body: some View {
        ZStack {
            switch step {
            case .recognizing:
                RecognizingView(request: request) { result in handle(result) }
                    .transition(.opacity)
            case .choose:
                ChoosePlaceView(photo: request.photo, places: choices, noMatch: noMatch) { picked in
                    place = picked; go(.question)
                }
                .transition(.opacity)
            case .question:
                if let p = current, let story = p.story {
                    QuestionView(place: p, story: story, photo: request.photo) { i in chosen = i; go(.reveal) }
                        .transition(.opacity)
                }
            case .reveal:
                if let story = current?.story {
                    RevealView(story: story, chosen: chosen) { go(story.lookCloser == nil ? .sticker : .lookCloser) }
                        .transition(.push(from: .trailing))
                }
            case .lookCloser:
                if let look = current?.story?.lookCloser {
                    LookCloserView(look: look) { go(.sticker) }
                        .transition(.push(from: .trailing))
                }
            case .sticker:
                if let sticker = current?.story?.sticker {
                    StickerEarnedView(sticker: sticker, onKeepExploring: { finish(.trip) }, onSeeAll: { finish(.stickers) })
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if step != .recognizing && step != .sticker {
                CloseButton { model.activeFlow = nil }
                    .padding(.trailing, 16).padding(.top, 4)
                    .environment(\.colorScheme, .dark)
            }
        }
        #if DEBUG
        .onAppear(perform: jumpForScreenshots)
        #endif
    }

    private func handle(_ result: RecognitionResult) {
        switch result {
        case .confident(let p): place = p; go(.question, animated: false)
        case .unsure(let ps): choices = ps; noMatch = false; go(.choose, animated: false)
        case .none(let ps): choices = ps; noMatch = true; go(.choose, animated: false)
        }
    }

    private func go(_ next: Step, animated: Bool = true) {
        withAnimation(animated ? Motion.glide : .easeInOut(duration: 0.25)) { step = next }
    }

    private func finish(_ tab: AppTab) {
        guard let p = current else { model.activeFlow = nil; return }
        if let story = p.story { RecallScheduler.schedule(for: p, story: story) }
        model.finishStory(at: p, goTo: tab)
    }

    #if DEBUG
    private func jumpForScreenshots() {
        let target: Step? = switch DebugLaunch.screen {
        case "question": .question
        case "reveal": .reveal
        case "closer": .lookCloser
        case "sticker": .sticker
        default: nil
        }
        if let target { place = request.suggested; step = target }
    }
    #endif
}

// MARK: - Recognising

/// While Vision compares the photo, the wait becomes part of the curiosity gap:
/// brackets lock on, a scan line sweeps, clues appear.
struct RecognizingView: View {
    let request: FlowRequest
    let onResult: (RecognitionResult) -> Void
    @Environment(AppModel.self) private var model
    @Environment(PlaceMatcher.self) private var matcher
    @Environment(PlaceRecognizer.self) private var location
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var locked = false
    @State private var scan = false
    @State private var clues: [String] = []
    @State private var visibleClues = 0
    @State private var thinking = ""
    @State private var flash = true

    var body: some View {
        let t = model.strings
        let place = request.suggested
        GeometryReader { geo in
            let start = CGRect(x: (geo.size.width - 270) / 2, y: geo.size.height * 0.3, width: 270, height: 320)
            let focus: CGRect = {
                if request.photo != nil {
                    return CGRect(x: geo.size.width * 0.12, y: geo.size.height * 0.28, width: geo.size.width * 0.76, height: geo.size.height * 0.4)
                }
                let img = ImageLoader.shared.cached(place.cameraImage)?.size ?? CGSize(width: 1, height: 1)
                return CoverLayout(imageSize: img, container: geo.size, anchor: CGPoint(x: place.cameraAnchor.x, y: place.cameraAnchor.y), zoom: 1.06).rect(place.focus)
            }()
            let box = locked ? focus : start

            ZStack(alignment: .topLeading) {
                if let photo = request.photo { CoverImage(image: photo) } else { CoverImage(place.cameraImage, anchor: place.cameraAnchor, zoom: 1.06) }
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
                        ForEach(Array((clues + [t("scan.gotItChip")]).enumerated()), id: \.offset) { i, clue in
                            let got = i == clues.count
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
                    Text(thinking.isEmpty ? t("scan.looking") : thinking).font(Typeface.hand(22)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 8)
                        .contentTransition(.opacity)
                }
                .padding(.bottom, 54)
            }
        }
        .overlay { Color.white.opacity(flash ? 1 : 0).allowsHitTesting(false) }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task { await run() }
    }

    private func run() async {
        // Every pause checks for cancellation, so leaving the screen stops the sequence.
        func pause(_ ms: Int) async -> Bool { (try? await Task.sleep(for: .milliseconds(reduce ? min(ms, 120) : ms))) != nil }
        let t = model.strings
        withAnimation(.easeOut(duration: 0.5)) { flash = false }
        // Recognition runs alongside the animation, so it never feels like waiting.
        let site = model.site
        let recognition = Task { () -> RecognitionResult in
            guard let photo = request.photo else { return .confident(request.suggested) }
            return await matcher.identify(photo, in: site, near: location.lastLocation)
        }
        guard await pause(250) else { recognition.cancel(); return }
        withAnimation(reduce ? .default : .spring(response: 0.7, dampingFraction: 0.72)) { locked = true }
        guard await pause(450) else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatCount(3, autoreverses: true)) { scan = true }
        let result = await recognition.value
        if case .confident(let p) = result { clues = model.site.place(id: p.id)?.clues ?? p.clues } else { clues = [] }
        for i in 1...clues.count + 1 {
            guard await pause(420) else { return }
            visibleClues = i
            if i == 2 { withAnimation { thinking = clues.prefix(2).joined(separator: "… ").lowercased().capitalizedFirst + "…" } }
        }
        if case .confident = result { withAnimation { thinking = t("scan.gotIt") }; Haptics.success() }
        guard await pause(700) else { return }
        onResult(result)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Shown when the photo matched several places (or none): the person picks, which also teaches us.
struct ChoosePlaceView: View {
    let photo: UIImage?
    let places: [Place]
    let noMatch: Bool
    let onPick: (Place) -> Void
    @Environment(AppModel.self) private var model
    @State private var shown = false

    var body: some View {
        let t = model.strings
        ZStack {
            if let photo { CoverImage(image: photo).blur(radius: 18).overlay(Color.black.opacity(0.45)).ignoresSafeArea() }
            else { Palette.piperno.ignoresSafeArea() }
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                Text(t(noMatch ? "scan.noneTitle" : "scan.unsureTitle")).font(Typeface.display(30)).foregroundStyle(.white)
                Text(t(noMatch ? "scan.noneBody" : "scan.unsureBody")).font(.system(size: 16)).foregroundStyle(.white.opacity(0.8))
                ForEach(Array(places.compactMap { model.site.place(id: $0.id) }.enumerated()), id: \.element.id) { i, p in
                    Button { Haptics.tap(); onPick(p) } label: {
                        HStack(spacing: 14) {
                            CoverImage(p.cameraImage, anchor: p.cameraAnchor).frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(Typeface.display(19)).foregroundStyle(.white)
                                Text(p.street).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                    }
                    .rise(shown, delay: 0.1 + Double(i) * 0.08)
                }
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
        .onAppear { shown = true }
    }
}

// MARK: - Question

/// Ask first, tell after. The photo shrinks to the top while the sheet springs up.
struct QuestionView: View {
    let place: Place
    let story: Story
    let photo: UIImage?
    let onAnswer: (Int) -> Void
    @Environment(AppModel.self) private var model
    @State private var shown = false
    @State private var selected: Int?
    @State private var confidence = 2

    var body: some View {
        let t = model.strings
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Palette.calce
                Group {
                    if let photo { CoverImage(image: photo) } else { CoverImage(place.cameraImage, anchor: .init(x: 0.40, y: 0.62)) }
                }
                .frame(height: shown ? geo.size.height * 0.42 : geo.size.height)
                .animation(Motion.glide, value: shown)

                VStack(alignment: .leading, spacing: 12) {
                    Capsule().fill(Palette.hair).frame(width: 38, height: 5).frame(maxWidth: .infinity)
                    Text(story.eyebrow).font(.system(size: 12, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(Palette.stone)
                        .rise(shown, delay: 0.45)
                    Text(story.question).font(Typeface.display(31, relativeTo: .title)).foregroundStyle(Palette.piperno)
                        .fixedSize(horizontal: false, vertical: true).minimumScaleFactor(0.8)
                        .rise(shown, delay: 0.5)
                    Spacer(minLength: 8)
                    ForEach(Array(story.answers.enumerated()), id: \.offset) { i, a in
                        Button(a) {
                            selected = i; Haptics.tap()
                            Task { try? await Task.sleep(for: .milliseconds(480)); onAnswer(i) }
                        }
                        .buttonStyle(AnswerButtonStyle(selected: selected == i, key: ["A", "B", "C", "D"][min(i, 3)]))
                        .disabled(selected != nil)
                        .rise(shown, delay: 0.65 + Double(i) * 0.09, distance: 18)
                    }
                    HStack(spacing: 10) {
                        Text(t("question.howSure")).font(.system(size: 15)).foregroundStyle(Palette.stone)
                        ForEach(1...3, id: \.self) { n in
                            Button { confidence = n; Haptics.tap() } label: {
                                Circle().fill(n <= confidence ? Palette.piperno : .clear)
                                    .overlay(Circle().stroke(Palette.piperno, lineWidth: 2)).frame(width: 14, height: 14)
                                    .padding(6)
                            }
                            .accessibilityLabel(t("question.sure\(n)"))
                        }
                    }
                    .frame(maxWidth: .infinity).rise(shown, delay: 0.95)
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
                .frame(height: geo.size.height * 0.62, alignment: .top)
                .background(Palette.calce, in: UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38))
                .shadow(color: .black.opacity(0.25), radius: 20, y: -6)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: shown ? 0 : geo.size.height)
                .animation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.12), value: shown)
            }
        }
        .ignoresSafeArea()
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
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @AppStorage(Settings.autoRead) private var autoRead = false
    @State private var narrator = Narrator()
    @State private var wipe = false
    @State private var shown = false
    @State private var stamped = false

    private var right: Bool { chosen == story.correctIndex }

    var body: some View {
        let t = model.strings
        VStack(alignment: .leading, spacing: 14) {
            Text(right ? t("reveal.right") : t("reveal.wrong", story.answers[min(chosen, story.answers.count - 1)]))
                .font(Typeface.hand(23)).foregroundStyle(right ? Palette.maiolica : Palette.stone)
                .mask(alignment: .leading) { Rectangle().scaleEffect(x: wipe ? 1 : 0, anchor: .leading) }
                .padding(.top, 8)
            Text(story.answerTitle).font(Typeface.display(46, relativeTo: .largeTitle)).foregroundStyle(Palette.piperno)
                .fixedSize(horizontal: false, vertical: true).minimumScaleFactor(0.7)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : -40).scaleEffect(shown ? 1 : 1.06, anchor: .leading)
                .animation(reduce ? nil : Motion.pop.delay(0.45), value: shown)
                .accessibilityAddTraits(.isHeader)
            Text(story.subtitle).font(Typeface.display(22)).foregroundStyle(Palette.azzurro).padding(.top, -6)
                .rise(shown, delay: 0.75, distance: 10)
            Text(story.body).font(.system(size: 18)).foregroundStyle(Palette.piperno).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .rise(shown, delay: 0.9)
            VerifiedPill(text: t("reveal.verified", story.source)).rise(shown, delay: 1.0)
            if let theory = story.theory {
                TheoryCard(theory: theory, stamped: stamped)
                    .opacity(shown ? 1 : 0).animation(.easeOut(duration: 0.4).delay(1.1), value: shown)
            }
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(Palette.tufo).frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("reveal.tellTonight")).font(.system(size: 11, weight: .bold)).textCase(.uppercase).kerning(1).foregroundStyle(Palette.stone)
                    Text(story.dinnerLine).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.piperno)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .rise(shown, delay: 1.3)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button { narrator.toggle(spoken, language: model.language) } label: {
                    Image(systemName: narrator.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.piperno)
                        .frame(width: 58, height: 58).background(Palette.sunk, in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(narrator.isSpeaking ? t("reveal.stopReading") : t("reveal.readAloud"))
                Button(story.lookCloser == nil ? t("reveal.collect") : t("reveal.lookCloser")) { Haptics.tap(); narrator.stop(); onNext() }
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
            Task {
                try? await Task.sleep(for: .milliseconds(1700))
                if story.theory != nil { Haptics.rigid() }
                if autoRead { narrator.toggle(spoken, language: model.language) }
            }
        }
        .onDisappear { narrator.stop() }
    }

    private var spoken: String { [story.answerTitle, story.subtitle, story.body].joined(separator: " ") }
}
