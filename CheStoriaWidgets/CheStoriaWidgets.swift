import ActivityKit
import SwiftUI
import WidgetKit

private enum WidgetPalette {
    static let tufo = Color(red: 0.91, green: 0.70, blue: 0.19)
    static let piperno = Color(red: 0.17, green: 0.19, blue: 0.18)
    static let calce = Color(red: 0.96, green: 0.96, blue: 0.94)
    static let mare = Color(red: 0.05, green: 0.23, blue: 0.36)
    static let maiolica = Color(red: 0.17, green: 0.52, blue: 0.38)
}

@main
struct CheStoriaWidgets: WidgetBundle {
    var body: some Widget {
        RecallWidget()
        SecretLiveActivity()
    }
}

// MARK: - "Yesterday's question" widget

struct RecallEntry: TimelineEntry {
    let date: Date
    let payload: RecallPayload?
}

struct RecallProvider: TimelineProvider {
    static let sample = RecallPayload(title: "Yesterday’s question", prompt: "Remember yesterday’s stone counter? Was it a bank, a bar or a bakery?",
                                      choices: ["Bank", "Bar", "Bakery"], placeName: "Thermopolium")
    func placeholder(in context: Context) -> RecallEntry { RecallEntry(date: .now, payload: Self.sample) }
    func getSnapshot(in context: Context, completion: @escaping (RecallEntry) -> Void) {
        completion(RecallEntry(date: .now, payload: SharedStore.loadRecall() ?? Self.sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecallEntry>) -> Void) {
        let entry = RecallEntry(date: .now, payload: SharedStore.loadRecall())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct RecallWidgetView: View {
    let entry: RecallEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let p = entry.payload {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(WidgetPalette.tufo).frame(width: 8, height: 8)
                    Text(p.title.uppercased()).font(.system(size: 10, weight: .bold)).kerning(0.6).foregroundStyle(.white.opacity(0.8))
                }
                if let result = p.resultText {
                    Text(result).font(.system(size: family == .systemSmall ? 15 : 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                } else {
                    Text(p.prompt).font(.system(size: family == .systemSmall ? 14 : 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .minimumScaleFactor(0.8)
                    if family != .systemSmall {
                        HStack(spacing: 6) {
                            ForEach(p.choices, id: \.self) { c in
                                Text(c).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.18), in: .capsule)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Text(p.placeName).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Circle().fill(WidgetPalette.tufo).frame(width: 10, height: 10)
                Text(SharedStore.widgetEmptyText).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
        }
    }
}

struct RecallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.chestoria.recall", provider: RecallProvider()) { entry in
            RecallWidgetView(entry: entry)
                .containerBackground(for: .widget) { LinearGradient(colors: [WidgetPalette.mare, Color(red: 0.12, green: 0.39, blue: 0.56)], startPoint: .top, endPoint: .bottom) }
                .widgetURL(URL(string: "chestoria://stickers"))
        }
        .configurationDisplayName("Yesterday’s question")
        .description("One quiet question about what you saw. Answering it helps you remember.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Live Activity: a secret nearby

struct SecretLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SecretActivityAttributes.self) { context in
            HStack(spacing: 14) {
                ZStack { Circle().fill(WidgetPalette.tufo); Circle().fill(WidgetPalette.piperno).padding(9) }.frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.headline).font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(context.state.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(context.state.meters) m").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            }
            .padding(16)
            .activityBackgroundTint(WidgetPalette.piperno.opacity(0.9))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "chestoria://snap"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Circle().fill(WidgetPalette.tufo).frame(width: 28, height: 28).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.meters) m").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.headline).font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(context.state.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Circle().fill(WidgetPalette.tufo).frame(width: 12, height: 12)
            } compactTrailing: {
                Text("\(context.state.meters) m").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
            } minimal: {
                Circle().fill(WidgetPalette.tufo).frame(width: 12, height: 12)
            }
            .widgetURL(URL(string: "chestoria://snap"))
            .keylineTint(WidgetPalette.tufo)
        }
    }
}
