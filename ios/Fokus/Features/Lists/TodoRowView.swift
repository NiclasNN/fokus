import SwiftUI

// MARK: - Delat tillstånd för hela listfliken

/// Ett öppet kort, en pågående markering och vilket ark som ska visas —
/// allt bor här så att varje skärm slipper bära sina egna kopior.
@MainActor
final class ListUI: ObservableObject {
    @Published var openID: String?
    @Published var selection: Set<String> = []
    @Published var whenTarget: String?
    @Published var moveTarget: String?
    @Published var repeatTarget: String?

    var selecting: Bool { !selection.isEmpty }
    func clearSelection() { selection.removeAll() }
}

// MARK: - Bocken

/// Things bock: ringen fylls medsols, sedan slår bocken in med fjäder.
/// Ungefär en halv sekund, med ljud och haptik — det är där belöningen sitter.
struct CheckCircle: View {
    var done: Bool
    var tint: Color
    var size: CGFloat = 22

    @State private var fill: CGFloat = 0
    @State private var mark: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().stroke(Palette.third.opacity(0.5), lineWidth: 1.6)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(tint, style: .init(lineWidth: size * 0.52, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .scaleEffect(0.5)                    // tjock stroke på halv radie = fylld skiva
                .clipShape(Circle())
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(mark)
                .opacity(mark > 0.05 ? 1 : 0)
        }
        .frame(width: size, height: size)
        .onAppear { snap(animated: false) }
        .onChange(of: done) { _, _ in snap(animated: true) }
    }

    private func snap(animated: Bool) {
        guard animated else { fill = done ? 1 : 0; mark = done ? 1 : 0; return }
        if done {
            withAnimation(.easeOut(duration: 0.28)) { fill = 1 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.2)) { mark = 1 }
        } else {
            withAnimation(.easeIn(duration: 0.16)) { mark = 0 }
            withAnimation(.easeIn(duration: 0.22).delay(0.05)) { fill = 0 }
        }
    }
}

/// Här möts appens två halvor: när ett pass kör på uppgiften byter bocken
/// plats med passets ring, mitt i listan. Man ser fokus hända där uppgifterna bor.
struct RunningRing: View {
    var fraction: Double
    var paused: Bool
    var tint: Color
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: 2.2)
            Circle()
                .trim(from: 0, to: max(0.003, fraction))
                .stroke(tint, style: .init(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: paused ? "pause.fill" : "timer")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.3), value: fraction)
    }
}

// MARK: - Markering (flerval)

struct SelectCircle: View {
    var on: Bool
    var tint: Color
    var body: some View {
        ZStack {
            Circle().stroke(Palette.third.opacity(0.5), lineWidth: 1.6)
            if on {
                Circle().fill(tint)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black)).foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Raden

/// Var raden ligger på skärmen — det magiska plusset behöver veta det
/// för att kunna räkna om en släpppunkt till ett index i listan.
struct RowFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct TodoRowView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: ListUI
    let todo: Todo
    var context: RowContext = .init()

    struct RowContext {
        var hideArea = false
        var hideWhen = false
    }

    private var isOpen: Bool { ui.openID == todo.id }
    private var tint: Color { store.tint(for: todo) }
    private var isRunning: Bool { store.s.timer.todoID == todo.id && store.s.timer.isLive }
    private var selected: Bool { ui.selection.contains(todo.id) }
    /// Things: kortet poppar ut medan resten av listan tonas bort.
    private var dimmed: Bool { ui.openID != nil && !isOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                leading
                VStack(alignment: .leading, spacing: 2.5) {
                    if isOpen {
                        TextField("Vad ska du göra?", text: store.binding(for: todo.id).title, axis: .vertical)
                            .font(Typo.rowBold)
                            .textInputAutocapitalization(.sentences)
                    } else {
                        Text(todo.title.isEmpty ? "Namnlös" : todo.title)
                            .font(Typo.row)
                            .foregroundStyle(todo.done ? Palette.second : Palette.label)
                            .strikethrough(todo.done, color: Palette.third)
                            .lineLimit(2)
                        meta
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .contentShape(Rectangle())
            .onTapGesture { tap() }

            if isOpen {
                TodoCardView(todo: store.binding(for: todo.id))
                    .padding(.leading, 33)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            // kortet ligger som ett ark PÅ listan, med luft runt om
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Palette.card)
                .shadow(color: .black.opacity(0.13), radius: 20, y: 7)
                .padding(.horizontal, 9)
                .opacity(isOpen ? 1 : 0)
        )
        .scaleEffect(isOpen ? 1.01 : 1, anchor: .center)
        .opacity(dimmed ? 0.32 : 1)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isOpen)
        .animation(.easeOut(duration: 0.22), value: dimmed)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: RowFrames.self, value: [todo.id: g.frame(in: .global)])
            }
        )
    }

    private func tap() {
        if ui.selecting {
            Haptics.tap()
            if selected { ui.selection.remove(todo.id) } else { ui.selection.insert(todo.id) }
            return
        }
        guard !todo.done else { return }
        Haptics.tap()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            ui.openID = isOpen ? nil : todo.id
        }
    }

    // MARK: - Vänsterkanten

    @ViewBuilder private var leading: some View {
        if ui.selecting {
            SelectCircle(on: selected, tint: tint).padding(.top, 1)
        } else if isRunning {
            Button {
                Haptics.tap()
                FocusLauncher.shared.jumpToFocus = true
            } label: {
                RunningRing(fraction: runFraction, paused: store.s.timer.status == .paused, tint: tint)
                    .padding(.top, 1)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                let next = !todo.done
                if next { Sound.shared.check(); Haptics.success() } else { Haptics.tap() }
                if isOpen { ui.openID = nil }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    store.setDone(todo.id, next)
                }
            } label: {
                CheckCircle(done: todo.done, tint: tint)
                    .padding(.top, 1)
                    .contentShape(Rectangle())
                    .frame(width: 30, height: 28, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }
    private var runFraction: Double {
        let d = Double(store.s.timer.durationSeconds)
        return d > 0 ? min(1, max(0, store.s.timer.remaining / d)) : 0
    }

    // MARK: - Högerkanten

    @ViewBuilder private var trailing: some View {
        if isRunning {
            Text(Sv.clock(store.s.timer.remaining))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
                .padding(.top, 1)
        } else if !todo.done && !isOpen && !ui.selecting {
            HStack(spacing: 7) {
                if todo.repeatRule != nil {
                    Image(systemName: "repeat").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.third)
                }
                Button {
                    FocusLauncher.shared.request(todo, store: store)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 30, height: 30)
                        .background(tint.opacity(0.12), in: Circle())
                }
                .buttonStyle(PressScale())
            }
            .padding(.top, -2)
        }
    }

    // MARK: - Metaraden

    @ViewBuilder private var meta: some View {
        let chips = chipList
        if !chips.isEmpty {
            HStack(spacing: 8) {
                ForEach(chips.indices, id: \.self) { i in chips[i] }
            }
        }
    }

    private var chipList: [AnyView] {
        var out: [AnyView] = []
        func chip(_ symbol: String?, _ text: String?, _ color: Color, pill: Bool = false) {
            out.append(AnyView(
                HStack(spacing: 3) {
                    if let s = symbol { Image(systemName: s).font(.system(size: 10, weight: .semibold)) }
                    if let t = text { Text(t) }
                }
                .font(Typo.meta)
                .foregroundStyle(color)
                .padding(.horizontal, pill ? 6 : 0).padding(.vertical, pill ? 1 : 0)
                .background(pill ? AnyShapeStyle(Palette.sunk) : AnyShapeStyle(Color.clear), in: Capsule())
            ))
        }

        if let a = Area.of(todo.areaID), !context.hideArea {
            chip(a.symbol, a.short, a.tint)
        }
        if !todo.done, !context.hideWhen {
            if let d = todo.when?.day { chip("calendar", Sv.day(d), Palette.second) }
            else if todo.when == .someday { chip("archivebox", "Någon gång", Palette.second) }
        }
        if todo.evening, !context.hideWhen { chip("moon.fill", "I kväll", Palette.evening) }
        if let d = todo.deadline, !todo.done {
            chip("flag.fill", Sv.deadline(d), d.daysFromToday > 2 ? Palette.second : Palette.deadline)
        }
        if !todo.checklist.isEmpty {
            chip("checklist", "\(todo.checklist.filter(\.done).count)/\(todo.checklist.count)", Palette.second)
        }
        if !todo.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chip("text.alignleft", nil, Palette.second)
        }
        if todo.focusedSeconds > 0 {
            chip("clock", Sv.short(seconds: todo.focusedSeconds), tint)
        }
        for t in todo.tags { chip(nil, t, Palette.second, pill: true) }
        return out
    }
}

// MARK: - Radens beteende i en List

/// Things gester, på Apples egna mekanismer: svep höger = När,
/// svep vänster = markera och radera, håll in = dra och släpp.
struct TodoRowBehaviour: ViewModifier {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: ListUI
    let todo: Todo

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(ui.openID == nil ? .visible : .hidden)
            .listRowSeparatorTint(Palette.hair)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 49 }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Haptics.tap(); ui.whenTarget = todo.id
                } label: { Label("När", systemImage: "calendar") }
                    .tint(Palette.today)
                Button {
                    Haptics.tap()
                    var t = todo
                    t.when = .on(DayKey.today); t.evening = false
                    store.update(t)
                } label: { Label("Idag", systemImage: "star.fill") }
                    .tint(Palette.upcoming)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    Haptics.warning()
                    if ui.openID == todo.id { ui.openID = nil }
                    withAnimation { store.delete(todo.id) }
                } label: { Label("Radera", systemImage: "trash") }
                Button {
                    Haptics.tap(); ui.moveTarget = todo.id
                } label: { Label("Flytta", systemImage: "square.stack.3d.up") }
                    .tint(Palette.anytime)
                Button {
                    Haptics.tap()
                    ui.openID = nil
                    ui.selection.insert(todo.id)
                } label: { Label("Markera", systemImage: "checkmark.circle") }
                    .tint(Palette.inbox)
            }
            // håll in och dra — ordningen i arrayen ÄR sorteringen
            .draggable(todo.id) {
                Text(todo.title.isEmpty ? "Uppgift" : todo.title)
                    .font(Typo.row).padding(10)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
            }
            .dropDestination(for: String.self) { ids, _ in
                guard let dragged = ids.first, dragged != todo.id else { return false }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    store.move(dragged, before: todo.id)
                }
                Haptics.press()
                return true
            }
    }
}

extension View {
    func todoRow(_ todo: Todo) -> some View { modifier(TodoRowBehaviour(todo: todo)) }
}

extension Store {
    /// Slår upp på id i både get och set — ett index hade blivit inaktuellt
    /// så fort en rad ovanför togs bort.
    func binding(for id: String) -> Binding<Todo> {
        Binding(
            get: { self.s.todos.first { $0.id == id } ?? Todo() },
            set: { nv in
                guard let i = self.index(of: id) else { return }
                self.s.todos[i] = nv
                self.save()
            }
        )
    }
}

/// Bryggan mellan listan och ratten.
///
/// ▶ i listan KASTAR dig inte till en annan flik — passet startar på plats och
/// raden byter bock mot ring. Det var det som gjorde att de två halvorna kändes
/// som två appar. Vill du se ratten trycker du på ringen.
@MainActor
final class FocusLauncher: ObservableObject {
    static let shared = FocusLauncher()
    @Published var needsArea: Todo?
    @Published var jumpToFocus = false

    /// Från listan: ladda och starta direkt, utan flikbyte.
    func request(_ t: Todo, store: Store) {
        guard !store.timeLocked else { Haptics.warning(); return }
        guard let area = store.area(for: t)?.id else {
            // En uppgift i Inkorgen hör inte till något livsområde. Utan ett
            // finns ingen ärlig plats att bokföra tiden på — fråga, gissa inte.
            Haptics.tap()
            needsArea = t
            return
        }
        load(t, area: area, store: store)
        store.startTimer()
    }

    /// Ladda utan att starta — används från Fokus egen kö.
    func load(_ t: Todo, store: Store) {
        guard !store.timeLocked else { Haptics.warning(); return }
        guard let area = store.area(for: t)?.id else { Haptics.tap(); needsArea = t; return }
        load(t, area: area, store: store)
    }

    func load(_ t: Todo, area: AreaID, store: Store) {
        store.s.timer.areaID = area
        store.s.timer.todoID = t.id
        store.s.timer.durationSeconds = t.durationMinutes * 60
        store.s.timer.elapsedBefore = 0
        store.s.timer.status = .idle
        store.s.timer.startedAt = nil
        store.save()
        Haptics.press()
    }
}
