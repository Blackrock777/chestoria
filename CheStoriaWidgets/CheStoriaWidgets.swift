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
        SecretLiveActivity()
    }
}

// MARK: - Live Activity: a secret nearby

struct SecretLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SecretActivityAttributes.self) { context in
            SecretActivityCard(context: context)
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
        .supplementalActivityFamilies([.small])
    }
}

private struct SecretActivityCard: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<SecretActivityAttributes>

    var body: some View {
        let small = family == .small
        let state = context.state
        HStack(spacing: small ? 8 : 14) {
            Image(systemName: "location.fill")
                .font(.system(size: small ? 11 : 17, weight: .semibold))
                .foregroundStyle(WidgetPalette.piperno)
                .frame(width: small ? 23 : 40, height: small ? 23 : 40)
                .background(WidgetPalette.tufo, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(small ? (state.watchTitle ?? state.headline) : state.headline)
                    .font(small ? .caption.weight(.semibold) : .headline)
                    .lineLimit(1)
                Text(context.isStale ? (state.watchExpired ?? context.attributes.siteName) :
                     (small ? (state.watchDetail ?? state.detail) : state.detail))
                    .font(small ? .caption2 : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(small ? 2 : nil)
            }
            Spacer(minLength: 0)
            if !context.isStale {
                Text("\(state.meters) m").font(small ? .caption.weight(.bold) : .title2.weight(.heavy))
                    .monospacedDigit().fixedSize()
            }
        }
        .padding(small ? 8 : 16)
        .activityBackgroundTint(WidgetPalette.piperno.opacity(0.9))
        .activitySystemActionForegroundColor(.white)
        .widgetURL(URL(string: "chestoria://snap"))
    }
}
