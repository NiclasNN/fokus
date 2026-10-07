import SwiftUI

/// Ratten. Ett upplyst föremål, inte en ritad båge.
///
/// Ett varv = 60 minuter; hela timmar lägger sig som varvringar innanför.
/// Draget räknar vinkelskillnad (inte absolut vinkel) och "lindar upp" den,
/// så man kan dra förbi tolv hur många gånger som helst utan att värdet hoppar.
struct DialView: View {
    @EnvironmentObject var store: Store

    @State private var minsFloat: Double = 25
    @State private var current: Int = 25
    @State private var prevAngle: Double = 0
    @State private var dragging = false
    @State private var started = false

    private let minMinutes = 1
    private let maxMinutes = 240
    /// Minuter innan värdet flippar. Hysteres hindrar fladder vid gränsen.
    private let hysteresis = 0.58
    /// Hur långt ljuset får töja sig inom ett steg, i grader.
    private let elastic = 0.55

    private var live: Bool { store.s.timer.isLive }
    private var tint: Color { Area.of(store.s.timer.areaID)?.tint ?? Palette.blue }

    private var laps: Int { max(0, (current - 1) / 60) }
    private var arcMinutes: Int { current - laps * 60 }          // alltid 1–60
    /// Under ett pass är ett varv hela passet; i vila är ett varv en timme.
    private var fraction: Double {
        if live {
            let d = Double(store.s.timer.durationSeconds)
            return d > 0 ? min(1, max(0, store.s.timer.remaining / d)) : 0
        }
        return Double(arcMinutes) / 60
    }
    private var headAngle: Double { fraction * 360 + (dragging ? elasticOffset : 0) }
    private var elasticOffset: Double {
        min(3.5, max(-3.5, (minsFloat - Double(current)) * 6 * elastic))
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                plate(size)
                ticks(size)
                groove(size)
                lapRings(size)
                arc(size)
                knob(size)
                face
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(drag(size: size, center: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)))
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { sync() }
        .onChange(of: store.s.timer.durationSeconds) { _, _ in if !dragging { sync() } }
        .onChange(of: store.s.timer.status) { _, _ in sync() }
    }

    private func sync() {
        let m = Int((Double(store.s.timer.durationSeconds) / 60).rounded())
        current = min(maxMinutes, max(minMinutes, m))
        minsFloat = Double(current)
    }

    // MARK: - Lagren

    private func plate(_ s: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(colors: [Palette.card, Palette.card.opacity(0.92)],
                               center: .init(x: 0.3, y: 0.22), startRadius: 0, endRadius: s * 0.7)
            )
            .shadow(color: .black.opacity(0.14), radius: s * 0.09, y: s * 0.035)
            .overlay(
                // auran: enda suddiga lagret, och den ändrar bara genomskinlighet
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.5), tint.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: s * 0.33))
                    .frame(width: s * 0.66, height: s * 0.66)
                    .opacity(store.s.timer.status == .paused ? 0.1 : dragging ? 0.42 : 0.3)
                    .animation(.easeOut(duration: 0.3), value: dragging)
            )
    }

    private func ticks(_ s: CGFloat) -> some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = size.width / 2
            for i in 0..<60 {
                let a = (Double(i) * 6 - 90) * .pi / 180
                let r1 = r * (i % 5 == 0 ? 0.832 : 0.855), r2 = r * 0.893
                var p = Path()
                p.move(to: CGPoint(x: c.x + r1 * cos(a), y: c.y + r1 * sin(a)))
                p.addLine(to: CGPoint(x: c.x + r2 * cos(a), y: c.y + r2 * sin(a)))
                ctx.stroke(p, with: .color(Palette.label.opacity(i % 5 == 0 ? 0.26 : 0.15)),
                           style: .init(lineWidth: s * 0.0048, lineCap: .round))
            }
        }
    }

    private func groove(_ s: CGFloat) -> some View {
        Circle()
            .stroke(Palette.label.opacity(0.07), lineWidth: s * 0.054)
            .padding(s * 0.115)
    }

    /// Hela timmar: en ring per varv, innanför skalan.
    private func lapRings(_ s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<max(0, live ? 0 : laps), id: \.self) { i in
                Circle()
                    .stroke(tint.opacity(0.4), lineWidth: s * 0.006)
                    .padding(s * (0.2 + Double(i) * 0.031))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: laps)
    }

    private func arc(_ s: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: max(0.0001, fraction))
            .stroke(
                AngularGradient(colors: [tint.opacity(0.85), tint], center: .center,
                                startAngle: .degrees(-90), endAngle: .degrees(270)),
                style: StrokeStyle(lineWidth: s * 0.039, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .padding(s * 0.115)
            .shadow(color: tint.opacity(dragging ? 0.5 : 0.3), radius: s * 0.03)
            .animation(dragging ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: fraction)
    }

    private func knob(_ s: CGFloat) -> some View {
        let r = s * 0.5 - s * 0.115
        return Circle()
            .fill(
                LinearGradient(colors: [.white, tint.opacity(0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: s * 0.004))
            .frame(width: s * (dragging ? 0.098 : 0.085), height: s * (dragging ? 0.098 : 0.085))
            .shadow(color: .black.opacity(0.25), radius: s * 0.012, y: s * 0.006)
            .offset(y: -r)
            .rotationEffect(.degrees(headAngle))
            .animation(dragging ? .interactiveSpring() : .spring(response: 0.45, dampingFraction: 0.8),
                       value: headAngle)
    }

    private var face: some View {
        VStack(spacing: 2) {
            Text((Area.of(store.s.timer.areaID)?.name ?? "").uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(1.7)
                .foregroundStyle(tint)
            Group {
                if live {
                    Text(Sv.clock(store.s.timer.remaining))
                        .font(.system(size: 54, weight: .ultraLight).monospacedDigit())
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(current < 60 ? "\(current)"
                             : (current % 60 == 0 ? "\(current / 60)" : "\(current / 60):\(String(format: "%02d", current % 60))"))
                            .font(.system(size: 60, weight: .ultraLight).monospacedDigit())
                        Text(current < 60 ? "MIN" : "TIM")
                            .font(.system(size: 11, weight: .bold))
                            .kerning(1.6)
                            .foregroundStyle(Palette.third)
                            .padding(.bottom, 12)
                    }
                }
            }
            .contentTransition(.numericText())
            .foregroundStyle(Palette.label)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Palette.second)
                .lineLimit(1)
                .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
    }

    private var subtitle: String {
        if store.s.timer.status == .paused { return "Pausad" }
        if let t = store.currentTodo, !t.title.isEmpty { return t.title }
        return store.s.timer.status == .running ? store.sessionTitle : "Redo att starta"
    }

    // MARK: - Gesten

    private func drag(size: CGFloat, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                guard !live else {
                    if !started { started = true; Haptics.warning() }
                    return
                }
                let dx = v.location.x - center.x, dy = v.location.y - center.y
                let radius = sqrt(dx * dx + dy * dy)
                let angle = (atan2(dy, dx) * 180 / .pi + 90 + 360)
                    .truncatingRemainder(dividingBy: 360)

                if !dragging {
                    // mitten är inte bandet — där ska man kunna trycka på siffran
                    guard radius > size * 0.2 else { return }
                    dragging = true
                    started = true
                    Haptics.prepareDial()
                    prevAngle = angle
                    // greppar man inte pärlan flyter ljuset dit fingret är
                    let onKnob = abs(((angle - Double(arcMinutes) * 6 + 540)
                        .truncatingRemainder(dividingBy: 360)) - 180) < 14
                    if !onKnob { flyTo(angle: angle) }
                    return
                }

                var d = angle - prevAngle
                if d > 180 { d -= 360 }
                if d < -180 { d += 360 }
                // ett hopp större än ett kvarts varv är en tappad händelse, inte en rörelse
                if abs(d) > 90 { prevAngle = angle; return }
                prevAngle = angle

                let want = minsFloat + d / 6                       // 6° = 1 minut
                minsFloat = min(Double(maxMinutes), max(Double(minMinutes), want))
                if minsFloat != want { Haptics.tap() }             // kanten
                if abs(minsFloat - Double(current)) > hysteresis {
                    commit(Int(minsFloat.rounded()))
                }
            }
            .onEnded { _ in
                guard dragging else { started = false; return }
                dragging = false
                started = false
                minsFloat = Double(current)
                store.save()
            }
    }

    private func flyTo(angle: Double) {
        var a = Int((angle / 6).rounded())
        if a == 0 { a = 60 }
        let lap = laps
        let target = [lap - 1, lap, lap + 1]
            .map { $0 * 60 + a }
            .filter { $0 >= minMinutes && $0 <= maxMinutes }
            .min { abs($0 - current) < abs($1 - current) } ?? current
        withAnimation(.spring(response: 0.33, dampingFraction: 0.78)) {
            commit(target)
            minsFloat = Double(target)
        }
    }

    private func commit(_ next: Int) {
        let clamped = min(maxMinutes, max(minMinutes, next))
        guard clamped != current else { return }
        let prev = current
        current = clamped
        store.s.timer.durationSeconds = clamped * 60
        store.s.settings.lastDurationMinutes = clamped

        let newLap = (clamped - 1) / 60 != (prev - 1) / 60
        let up = clamped > prev
        if newLap            { Haptics.hourTick(); Sound.shared.detent(.hour, up: up) }
        else if clamped % 5 == 0 { Haptics.fiveTick(); Sound.shared.detent(.five, up: up) }
        else                 { Haptics.tick();     Sound.shared.detent(.minute, up: up) }
    }
}
