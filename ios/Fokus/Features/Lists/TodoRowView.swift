import SwiftUI

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
                .scaleEffect(0.5)                    // en tjock stroke på halv radie = fylld skiva
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
    let todo: Todo
    var context: RowContext = .init()
    @Binding var openID: String?

    struct RowContext {
        var hideProject = false
        var hideArea = false
        var hideWhen = false
    }

    private var isOpen: Bool { openID == todo.id }
    private var tint: Color { store.tint(for: todo) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                Button {
                    let next = !todo.done
                    if next { Sound.shared.check(); Haptics.success() } else { Haptics.tap() }
                    if isOpen { openID = nil }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        store.setDone(todo.id, next)
                    }
                } label: {
                    CheckCircle(done: todo.done, tint: tint)
                        .padding(.top, 1)
                        .contentShape(Rectangle())
                        .frame(width: 30, height: 30, alignment: .leading)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
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
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !todo.done else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                        openID = isOpen ? nil : todo.id
                    }
                }

                if !todo.done && !isOpen {
                    Button {
                        FocusLauncher.shared.request(todo, store: store)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 32, height: 32)
                            .background(tint.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(PressScale())
                }
            }

            if isOpen {
                TodoCardView(todo: store.binding(for: todo.id), openID: $openID)
                    .padding(.leading, 41)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isOpen ? Palette.card : .clear)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: RowFrames.self, value: [todo.id: g.frame(in: .global)])
            }
        )
    }

    // MARK: - Metaraden

    @ViewBuilder private var meta: some View {
        let chips = chipList
        if !chips.isEmpty {
            HStack(spacing: 9) {
                ForEach(chips.indices, id: \.self) { i in chips[i] }
            }
        }
    }

    private var chipList: [AnyView] {
        var out: [AnyView] = []
        func chip(_ symbol: String?, _ text: String?, _ color: Color, pill: Bool = false) {
            out.append(AnyView(
                HStack(spacing: 3.5) {
                    if let s = symbol { Image(systemName: s).font(.system(size: 10.5, weight: .semibold)) }
                    if let t = text { Text(t) }
                }
                .font(Typo.meta)
                .foregroundStyle(color)
                .padding(.horizontal, pill ? 7 : 0).padding(.vertical, pill ? 1.5 : 0)
                .background(pill ? AnyShapeStyle(Palette.sunk) : AnyShapeStyle(Color.clear), in: Capsule())
            ))
        }

        if let p = store.project(todo.projectID), !context.hideProject {
            chip("chevron.right", p.title, tint)
        } else if let a = Area.of(todo.areaID), todo.projectID == nil, !context.hideArea {
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

/// Att starta ett pass från en rad kräver ibland en fråga först.
/// Den här bär svaret tillbaka till fokusfliken.
@MainActor
final class FocusLauncher: ObservableObject {
    static let shared = FocusLauncher()
    @Published var needsArea: Todo?
    @Published var jumpToFocus = false

    func request(_ t: Todo, store: Store) {
        guard !store.timeLocked else { Haptics.warning(); return }
        guard let area = store.area(for: t)?.id else {
            // En uppgift i Inkorgen hör inte till något livsområde. Utan ett
            // finns ingen ärlig plats att bokföra tiden på — fråga, gissa inte.
            Haptics.tap()
            needsArea = t
            return
        }
        launch(t, area: area, store: store)
    }
    func launch(_ t: Todo, area: AreaID, store: Store) {
        store.s.timer.areaID = area
        store.s.timer.todoID = t.id
        store.s.timer.durationSeconds = t.durationMinutes * 60
        store.s.timer.elapsedBefore = 0
        store.s.timer.status = .idle
        store.s.timer.startedAt = nil
        store.save()
        Haptics.press()
        jumpToFocus = true
    }
}
