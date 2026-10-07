import SwiftUI

struct FocusView: View {
    @EnvironmentObject var store: Store
    @State private var showPresets = false

    private var tint: Color { Area.of(store.s.timer.areaID)?.tint ?? Palette.blue }
    private let presets = [5, 15, 25, 45, 60, 90]

    /// Remsan ÄR din Idag-lista för det här området. Fokus utför planen du
    /// gjorde i Things-delen — den hittar inte på en egen ordning.
    /// Finns inget planerat idag visas det som går att ta tag i ändå.
    private var strip: [Todo] {
        let today = DayKey.today
        let inArea = store.s.todos.filter {
            !$0.isHeading && !$0.done && store.area(for: $0)?.id == store.s.timer.areaID
        }
        let planned = inArea.filter { t in
            (t.when?.day.map { $0 <= today } ?? false) || (t.deadline.map { $0 <= today } ?? false)
        }
        if !planned.isEmpty { return planned }
        return inArea.filter {
            $0.when != .someday && !($0.when?.day.map { $0 > today } ?? false)
        }
    }
    private var stripIsToday: Bool {
        let today = DayKey.today
        return strip.contains { t in
            (t.when?.day.map { $0 <= today } ?? false) || (t.deadline.map { $0 <= today } ?? false)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Rummet tar färg av valt livsområde. Föremålen förblir neutrala.
                tint.opacity(0.07).ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack { corner(.socialt); Spacer(); corner(.struktur) }
                    Spacer(minLength: 4)
                    VStack(spacing: 14) {
                        DialView()
                            .frame(maxHeight: min(geo.size.height * 0.42, 300))
                        taskStrip
                        presetRow
                        controls
                    }
                    Spacer(minLength: 4)
                    HStack { corner(.pengar); Spacer(); corner(.halsa) }
                }
                .padding(.horizontal, 16)
            }
            .animation(.easeInOut(duration: 0.5), value: store.s.timer.areaID)
        }
        .navigationBarHidden(true)
    }

    // MARK: - Hörnen

    private func corner(_ id: AreaID) -> some View {
        let a = Area.of(id)!
        let on = store.s.timer.areaID == id
        let hasOpen = store.areaBadge(id) > 0
        let todayCount = store.todayCount(in: id)
        return Button {
            guard !store.timeLocked else { Haptics.warning(); return }
            Haptics.press()
            store.s.timer.areaID = id
            store.s.timer.todoID = nil
            store.save()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: a.symbol).font(.system(size: 21, weight: .semibold))
                Text(a.short).font(.system(size: 10.5, weight: .bold)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(width: 78, height: 78)
            .background(
                LinearGradient(colors: [a.tint.opacity(0.92), a.tint],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 23, style: .continuous)
            )
            .overlay(alignment: .topTrailing) {
                // Samma plats som pricken alltid haft, men den säger nu hur
                // många uppgifter som faktiskt väntar idag i området.
                if todayCount > 0 {
                    Text("\(todayCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(a.tint)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(.white, in: Capsule())
                        .padding(7)
                } else if hasOpen {
                    Circle().fill(.white).frame(width: 6, height: 6).padding(9)
                }
            }
            .shadow(color: a.tint.opacity(on ? 0.45 : 0.22), radius: on ? 14 : 8, y: 5)
            .scaleEffect(on ? 1.06 : 0.94)
            .opacity(store.timeLocked && !on ? 0.4 : on ? 1 : 0.8)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: on)
    }

    // MARK: - Uppgiftsremsan

    private var taskStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if strip.isEmpty {
                    Text("Inget planerat i \(Area.of(store.s.timer.areaID)?.short ?? "") — lägg till under Listor")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.third)
                        .padding(.horizontal, 6)
                } else {
                    ForEach(strip) { t in
                        let on = store.s.timer.todoID == t.id
                        Button {
                            guard !store.timeLocked else { Haptics.warning(); return }
                            Haptics.tap()
                            if on { store.s.timer.todoID = nil }
                            else {
                                store.s.timer.todoID = t.id
                                store.s.timer.durationSeconds = t.durationMinutes * 60
                            }
                            store.save()
                        } label: {
                            HStack(spacing: 9) {
                                Text(t.title.isEmpty ? "Namnlös" : t.title)
                                    .font(.system(size: 14.5, weight: .medium))
                                    .lineLimit(1)
                                    .foregroundStyle(on ? .white : Palette.label)
                                // Den valda uppgiften går att bocka av här —
                                // samma uppgift, samma bock, som i listan.
                                if on {
                                    Button {
                                        Sound.shared.check(); Haptics.success()
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                            store.setDone(t.id, true)
                                        }
                                        store.s.timer.todoID = nil
                                        store.save()
                                    } label: {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .black))
                                            .foregroundStyle(.white)
                                            .frame(width: 24, height: 24)
                                            .background(.white.opacity(0.24), in: Circle())
                                    }
                                    .buttonStyle(PressScale())
                                    .disabled(store.timeLocked)
                                }
                            }
                            .padding(.leading, 15).padding(.trailing, on ? 6 : 15)
                            .padding(.vertical, on ? 6 : 10)
                            .background(on ? AnyShapeStyle(tint) : AnyShapeStyle(Palette.card),
                                        in: Capsule())
                            .overlay(Capsule().stroke(Palette.hair, lineWidth: on ? 0 : 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 42)
        .opacity(store.timeLocked ? 0.45 : 1)
    }

    // MARK: - Förval

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(presets, id: \.self) { m in
                    let on = Int((Double(store.s.timer.durationSeconds) / 60).rounded()) == m
                    Button {
                        guard !store.timeLocked else { Haptics.warning(); return }
                        Haptics.tap()
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            store.s.timer.durationSeconds = m * 60
                        }
                        store.s.settings.lastDurationMinutes = m
                        store.save()
                    } label: {
                        Text(m < 60 ? "\(m) min" : "\(m / 60) h")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(on ? tint : Palette.second)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(on ? AnyShapeStyle(tint.opacity(0.14)) : AnyShapeStyle(Palette.card),
                                        in: Capsule())
                            .overlay(Capsule().stroke(on ? tint.opacity(0.45) : Palette.hair, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 36)
        .opacity(store.timeLocked ? 0.45 : 1)
    }

    // MARK: - Knapparna

    private var controls: some View {
        HStack(spacing: 16) {
            ghost("arrow.counterclockwise", disabled: store.s.timer.status == .idle
                                                      && store.s.timer.elapsedBefore == 0) {
                store.resetTimer()
            }
            Button {
                store.s.timer.status == .running ? store.pauseTimer() : store.startTimer()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: store.s.timer.status == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                    Text(store.s.timer.status == .running ? "Pausa"
                         : store.s.timer.status == .paused ? "Fortsätt" : "Starta")
                        .font(.system(size: 16.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(minWidth: 160, minHeight: 54)
                .background(
                    LinearGradient(colors: [tint.opacity(0.88), tint],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule()
                )
                .shadow(color: tint.opacity(0.4), radius: 14, y: 6)
            }
            .buttonStyle(PressScale())
            ghost("checkmark", disabled: !store.s.timer.isLive) { store.finishEarly() }
        }
    }

    private func ghost(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.second)
                .frame(width: 50, height: 50)
                .background(Palette.card, in: Circle())
                .overlay(Circle().stroke(Palette.hair, lineWidth: 0.5))
        }
        .buttonStyle(PressScale())
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
