import SwiftUI

/// Fokus är inte en egen ö. Det är utförandevyn för listan: uppgiften är
/// ämnet, ratten är instrumentet, och nästa uppgift i Idag står redan på tur.
struct FocusView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var launcher = FocusLauncher.shared
    @State private var showPicker = false

    private var task: Todo? { store.currentTodo }
    private var tint: Color { task.map { store.tint(for: $0) } ?? (Area.of(store.s.timer.areaID)?.tint ?? Palette.blue) }
    private let presets = [5, 15, 25, 45, 60, 90]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    contextLine
                    DialView().frame(height: 290)
                    subject
                    if !store.timeLocked { presetRow }
                    controls
                    nextUp
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(
                // samma neutrala yta som Listor; området är accent, inte kuliss
                ZStack {
                    Palette.bg
                    tint.opacity(0.05)
                }
                .ignoresSafeArea()
            )
            .navigationTitle("Fokus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.streak > 0 {
                        Label("\(store.streak)", systemImage: "flame.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.today)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: store.s.timer.todoID)
            .sheet(isPresented: $showPicker) {
                TodayPickerSheet().environmentObject(store)
            }
        }
    }

    // MARK: - Vad du utför

    private var contextLine: some View {
        HStack(spacing: 7) {
            if task != nil {
                Image(systemName: "star.fill").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.today)
                Text("IDAG").font(.system(size: 11, weight: .bold)).kerning(1.4)
                Text("·").foregroundStyle(Palette.third)
                Text("\(store.todayRemaining) kvar").font(.system(size: 12, weight: .medium))
            } else {
                Image(systemName: "timer").font(.system(size: 11, weight: .bold))
                Text("FRITT PASS").font(.system(size: 11, weight: .bold)).kerning(1.4)
            }
            Spacer()
        }
        .foregroundStyle(Palette.second)
    }

    // MARK: - Ämnet: uppgiften, med sin checklista levande

    @ViewBuilder private var subject: some View {
        if let t = task {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 11) {
                    Button {
                        Sound.shared.check(); Haptics.success()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            store.setDone(t.id, true)
                            store.s.timer.todoID = nil
                        }
                    } label: { CheckCircle(done: false, tint: tint, size: 24) }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title.isEmpty ? "Namnlös" : t.title)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Palette.label)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 9) {
                            if let p = store.project(t.projectID) {
                                chip("chevron.right", p.title, tint)
                            } else if let a = Area.of(t.areaID) {
                                chip(a.symbol, a.short, a.tint)
                            }
                            if let d = t.deadline {
                                chip("flag.fill", Sv.deadline(d),
                                     d.daysFromToday > 2 ? Palette.second : Palette.deadline)
                            }
                            if t.focusedSeconds > 0 {
                                chip("clock", Sv.short(seconds: t.focusedSeconds), tint)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Button { Haptics.tap(); store.s.timer.todoID = nil; store.save() } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.third).frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.timeLocked)
                    .opacity(store.timeLocked ? 0 : 1)
                }

                // Stegen går att bocka av MEDAN passet löper — det är därför
                // uppgiften ligger här och inte bara som en rubrik.
                if !t.checklist.isEmpty {
                    Divider().padding(.vertical, 11)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(store.binding(for: t.id).checklist) { $item in
                            HStack(spacing: 9) {
                                Button {
                                    Haptics.tap()
                                    if !item.done { Sound.shared.check() }
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        item.done.toggle()
                                    }
                                } label: { CheckCircle(done: item.done, tint: tint, size: 18) }
                                .buttonStyle(.plain)
                                Text(item.title.isEmpty ? "Steg" : item.title)
                                    .font(.system(size: 14.5))
                                    .foregroundStyle(item.done ? Palette.third : Palette.second)
                                    .strikethrough(item.done, color: Palette.third)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheetCard()
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            VStack(spacing: 13) {
                Button { Haptics.tap(); showPicker = true } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "star.fill").font(.system(size: 13, weight: .bold))
                        Text("Välj något från Idag").font(.system(size: 15.5, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.third)
                    }
                    .foregroundStyle(Palette.label)
                    .padding(15)
                    .frame(maxWidth: .infinity)
                    .sheetCard()
                }
                .buttonStyle(PressScale())

                // Utan uppgift måste området väljas för hand — tiden ska ändå
                // bokföras någonstans.
                HStack(spacing: 7) {
                    ForEach(Area.all) { a in
                        let on = store.s.timer.areaID == a.id
                        Button {
                            guard !store.timeLocked else { Haptics.warning(); return }
                            Haptics.tap(); store.s.timer.areaID = a.id; store.save()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: a.symbol).font(.system(size: 14, weight: .semibold))
                                Text(a.short).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                            }
                            .foregroundStyle(on ? .white : a.tint)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(on ? AnyShapeStyle(a.tint) : AnyShapeStyle(a.tint.opacity(0.12)),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
        }
    }

    private func chip(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 3.5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text).lineLimit(1)
        }
        .font(Typo.meta).foregroundStyle(color)
    }

    // MARK: - Förval

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(presets, id: \.self) { m in
                    let on = Int((Double(store.s.timer.durationSeconds) / 60).rounded()) == m
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            store.s.timer.durationSeconds = m * 60
                        }
                        store.s.settings.lastDurationMinutes = m
                        // uppgiften bär sin egen längd — ändrar du här, ändras den
                        if var t = task { t.durationMinutes = m; store.update(t) }
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
            .padding(.horizontal, 1)
        }
        .frame(height: 36)
    }

    // MARK: - Knapparna

    private var controls: some View {
        HStack(spacing: 16) {
            ghost("arrow.counterclockwise",
                  disabled: store.s.timer.status == .idle && store.s.timer.elapsedBefore == 0) {
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
                .shadow(color: tint.opacity(0.35), radius: 14, y: 6)
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

    // MARK: - Kön

    @ViewBuilder private var nextUp: some View {
        if let next = store.nextInToday(after: task?.id), next.id != task?.id {
            Button {
                guard !store.timeLocked else { Haptics.warning(); return }
                FocusLauncher.shared.load(next, store: store)
            } label: {
                HStack(spacing: 10) {
                    Text("NÄSTA").font(.system(size: 10.5, weight: .bold)).kerning(1.2)
                        .foregroundStyle(Palette.third)
                    Text(next.title.isEmpty ? "Namnlös" : next.title)
                        .font(.system(size: 14.5)).foregroundStyle(Palette.label).lineLimit(1)
                    Spacer()
                    Text("\(next.durationMinutes) min")
                        .font(Typo.meta).foregroundStyle(store.tint(for: next))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.third)
                }
                .padding(.horizontal, 15).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .sheetCard()
            }
            .buttonStyle(PressScale())
            .opacity(store.timeLocked ? 0.4 : 1)
        }
    }
}

/// Välj bland dagens uppgifter utan att lämna Fokus.
struct TodayPickerSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let items = store.items(in: .today).filter { !$0.done }
                if items.isEmpty {
                    Text("Inget planerat idag. Lägg till något under Listor → Idag.")
                        .font(.system(size: 14)).foregroundStyle(Palette.second)
                } else {
                    ForEach(items) { t in
                        Button {
                            FocusLauncher.shared.load(t, store: store)
                            dismiss()
                        } label: {
                            HStack(spacing: 11) {
                                Circle().fill(store.tint(for: t)).frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title.isEmpty ? "Namnlös" : t.title)
                                        .font(Typo.row).foregroundStyle(Palette.label)
                                    if let a = store.area(for: t) {
                                        Text(a.short).font(Typo.meta).foregroundStyle(Palette.third)
                                    }
                                }
                                Spacer()
                                Text("\(t.durationMinutes) min")
                                    .font(Typo.meta).foregroundStyle(Palette.third)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Idag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } } }
        }
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
