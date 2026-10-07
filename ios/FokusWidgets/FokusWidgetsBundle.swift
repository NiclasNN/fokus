import WidgetKit
import SwiftUI
import ActivityKit

@main
struct FokusWidgetsBundle: WidgetBundle {
    var body: some Widget { FokusLiveActivity() }
}

/// Passet på låsskärmen och i Dynamic Island.
///
/// Nedräkningen ritas med `Text(timerInterval:)`. Systemet animerar den själv,
/// så siffrorna fortsätter ticka med släckt skärm utan att appen behöver vara
/// vaken och utan en enda uppdatering skickad från appen.
struct FokusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FokusAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.18))
                .activitySystemActionForegroundColor(Color(hex: context.attributes.tintHex))
        } dynamicIsland: { context in
            let tint = Color(hex: context.attributes.tintHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context, size: 20, tint: tint)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(context.attributes.areaName.uppercased())
                            .font(.system(size: 9, weight: .bold)).kerning(1)
                            .foregroundStyle(tint)
                        Text(context.attributes.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    progress(context, tint: tint)
                }
            } compactLeading: {
                Image(systemName: context.state.paused ? "pause.fill" : "timer")
                    .foregroundStyle(tint)
            } compactTrailing: {
                countdown(context, size: 13, tint: tint)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.state.paused ? "pause.fill" : "timer")
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }

    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<FokusAttributes>,
                           size: CGFloat, tint: Color) -> some View {
        Group {
            if context.state.paused {
                Text(FokusClock.text(context.state.remaining))
            } else {
                Text(timerInterval: Date.now...context.state.endsAt,
                     pauseTime: nil, countsDown: true, showsHours: false)
                    .multilineTextAlignment(.trailing)
            }
        }
        .font(.system(size: size, weight: .semibold).monospacedDigit())
        .foregroundStyle(context.state.paused ? Color.secondary : tint)
    }

    @ViewBuilder
    private func progress(_ context: ActivityViewContext<FokusAttributes>, tint: Color) -> some View {
        if context.state.paused {
            ProgressView(value: 1 - context.state.remaining / Double(max(1, context.attributes.totalSeconds)))
                .tint(tint)
        } else {
            ProgressView(timerInterval: context.state.endsAt.addingTimeInterval(-Double(context.attributes.totalSeconds))...context.state.endsAt,
                         countsDown: false)
                .tint(tint)
                .labelsHidden()
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<FokusAttributes>

    var body: some View {
        let tint = Color(hex: context.attributes.tintHex)
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(tint.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: context.state.paused
                          ? context.state.remaining / Double(max(1, context.attributes.totalSeconds)) : 1)
                    .stroke(tint, style: .init(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: context.state.paused ? "pause.fill" : "timer")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.areaName.uppercased())
                    .font(.system(size: 10, weight: .bold)).kerning(1.1)
                    .foregroundStyle(tint)
                Text(context.attributes.title)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                if context.state.paused {
                    Text("Pausad").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)

            Group {
                if context.state.paused {
                    Text(FokusClock.text(context.state.remaining))
                } else {
                    Text(timerInterval: Date.now...context.state.endsAt,
                         pauseTime: nil, countsDown: true, showsHours: false)
                        .multilineTextAlignment(.trailing)
                }
            }
            .font(.system(size: 26, weight: .light).monospacedDigit())
            .foregroundStyle(context.state.paused ? Color.secondary : .primary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
