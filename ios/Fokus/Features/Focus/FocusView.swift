import SwiftUI

struct FocusView: View {
    @EnvironmentObject var store: Store
    @State private var showPresets = false

    private var tint: Color { Area.of(store.s.timer.areaID)?.tint ?? Palette.blue }
    private let presets = [5, 15, 25, 45, 60, 90]

    /// Dagens plan styr remsan: uppgiften hör till området direkt eller via sitt
    /// projekt, och "någon gång" ska inte ligga och skräpa på fokusskärmen.
    private var strip: [Todo] {
        let today = DayKey.today
        func rank(_ t: Todo) -> Int {
            if let d = t.when?.day, d <= today { return 0 }
            if let d = t.deadline, d <= DayKey.today(offsetBy: 3) { return 1 }
            return 2
        }
        return store.s.todos
            .filter { !$0.isHeading && !$0.done && $0.when != .someday
                      && store.area(for: $0)?.id == store.s.timer.areaID }
            .sorted { rank($0) < rank($1) }
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
                if hasOpen {
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
                    Text("Inga uppgifter i \(Area.of(store.s.timer.areaID)?.short ?? "")")
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
                            Text(t.title.isEmpty ? "Namnlös" : t.title)
                                .font(.system(size: 14.5, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(on ? .white : Palette.label)
                                .padding(.horizontal, 15).padding(.vertical, 10)
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
