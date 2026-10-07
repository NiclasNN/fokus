import SwiftUI

enum Route: Hashable {
    case list(SmartList)
    case area(AreaID)
    case project(String)
}

/// Rader i visningsordning, och dagsgruppernas ytor. Det magiska plusset
/// läser båda för att kunna räkna om en släpppunkt till ett index.
struct RowOrder: PreferenceKey {
    static var defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) { value += nextValue() }
}
struct GroupFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct ListsHomeView: View {
    @EnvironmentObject var store: Store
    @StateObject private var launcher = FocusLauncher.shared

    @State private var path: [Route] = []
    @State private var openID: String?
    @State private var query = ""
    @State private var frames: [String: CGRect] = [:]
    @State private var order: [String] = []
    @State private var groups: [String: CGRect] = [:]
    @State private var newProjectArea: AreaID??

    private var route: Route? { path.last }

    var body: some View {
        NavigationStack(path: $path) {
            home
                .navigationDestination(for: Route.self) { r in
                    switch r {
                    case .list(let l):   SmartListView(list: l, openID: $openID)
                    case .area(let a):   AreaView(area: a, openID: $openID)
                    case .project(let p): ProjectDetailView(projectID: p, openID: $openID)
                    }
                }
        }
        .onPreferenceChange(RowFrames.self)   { frames = $0 }
        .onPreferenceChange(RowOrder.self)    { order = $0 }
        .onPreferenceChange(GroupFrames.self) { groups = $0 }
        .overlay(alignment: .bottomTrailing) {
            MagicPlus(route: route, frames: frames, order: order, groups: groups) { index, heading, day in
                create(at: index, heading: heading, day: day)
            }
            .padding(.trailing, 18)
            .padding(.bottom, 14)
        }
        .sheet(item: Binding(get: { launcher.needsArea.map(IdentifiedTodo.init) },
                             set: { if $0 == nil { launcher.needsArea = nil } })) { wrap in
            MoveSheet(todo: store.binding(for: wrap.todo.id), forFocus: true)
                .presentationDetents([.medium, .large])
                .environmentObject(store)
        }
        .sheet(item: Binding(get: { newProjectArea.map { AreaBox(id: $0) } },
                             set: { if $0 == nil { newProjectArea = nil } })) { box in
            NewProjectSheet(area: box.id) { p in
                newProjectArea = nil
                path.append(.project(p.id))
            }
            .environmentObject(store)
        }
    }

    // MARK: - Hemskärmen

    private var home: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    listsCard
                    SectionLabel("Livsområden")
                    areasCard
                } else {
                    searchResults
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .background(Palette.bg)
        .navigationTitle("Listor")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Sök uppgifter och projekt")
    }

    private var listsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(SmartList.allCases.enumerated()), id: \.element) { i, l in
                NavRow(symbol: l.symbol, title: l.title, tint: l.tint,
                       badge: store.count(l)) { path.append(.list(l)) }
                if i < SmartList.allCases.count - 1 { Hairline(inset: 54) }
            }
        }
        .sheetCard()
    }

    private var areasCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(Area.all.enumerated()), id: \.element) { i, a in
                NavRow(symbol: a.symbol, title: a.name, tint: a.tint,
                       badge: store.areaBadge(a.id)) { path.append(.area(a.id)) }
                ForEach(store.projects(in: a.id)) { p in
                    Hairline(inset: 54)
                    let pr = store.progress(p.id)
                    NavRow(pie: pr.total == 0 ? 0 : Double(pr.done) / Double(pr.total),
                           title: p.title, tint: a.tint, indent: 24,
                           trailing: pr.total > 0 ? "\(pr.done)/\(pr.total)" : nil) {
                        path.append(.project(p.id))
                    }
                }
                if i < Area.all.count - 1 { Hairline(inset: 54) }
            }
        }
        .sheetCard()
    }

    @ViewBuilder private var searchResults: some View {
        let hits = store.search(query)
        if hits.todos.isEmpty && hits.projects.isEmpty {
            EmptyNote(title: "Ingen träff",
                      body: "Inget som heter ”\(query.trimmingCharacters(in: .whitespaces))”.")
        } else {
            if !hits.projects.isEmpty {
                SectionLabel("Projekt")
                VStack(spacing: 0) {
                    ForEach(Array(hits.projects.enumerated()), id: \.element) { i, p in
                        let pr = store.progress(p.id)
                        NavRow(pie: pr.total == 0 ? 0 : Double(pr.done) / Double(pr.total),
                               title: p.title, tint: Area.of(p.areaID)?.tint ?? Palette.inbox) {
                            path.append(.project(p.id))
                        }
                        if i < hits.projects.count - 1 { Hairline(inset: 54) }
                    }
                }
                .sheetCard()
            }
            if !hits.todos.isEmpty {
                SectionLabel("Uppgifter")
                TodoCard(todos: hits.todos, openID: $openID)
            }
        }
    }

    // MARK: - Nytt

    private func create(at index: Int?, heading: Bool, day: DayKey?) {
        if heading, case .project(let pid)? = route {
            var h = Todo(); h.kind = .heading; h.projectID = pid
            store.insert(h, at: index)
            Haptics.success()
            openID = nil
            return
        }
        var t = Todo()
        t.durationMinutes = store.s.settings.lastDurationMinutes
        switch route {
        case .list(let l):
            switch l {
            case .today:    t.when = .on(DayKey.today)
            case .someday:  t.when = .someday
            case .upcoming: t.when = .on(day ?? DayKey.today(offsetBy: 1))
            default: break
            }
        case .area(let a):
            t.areaID = a
        case .project(let pid):
            t.projectID = pid
            t.areaID = store.project(pid)?.areaID
        case .none:
            break                                   // hemskärmen: hamnar i Inkorgen
        }
        if case .list(.upcoming) = route, let d = day { t.when = .on(d) }
        store.insert(t, at: index)
        Haptics.success()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { openID = t.id }
    }
}

private struct IdentifiedTodo: Identifiable { let todo: Todo; var id: String { todo.id } }
private struct AreaBox: Identifiable { let id: AreaID?; var idString: String { id?.rawValue ?? "inbox" } }
extension AreaBox { var identity: String { idString } }

// MARK: - Byggstenar

struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(Typo.section).kerning(0.8)
                .foregroundStyle(Palette.third)
            Spacer()
        }
        .padding(.top, 22).padding(.bottom, 7).padding(.horizontal, 4)
    }
}

struct EmptyNote: View {
    let title: String
    let message: String
    init(title: String, body: String) { self.title = title; self.message = body }

    var body: some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 16.5, weight: .semibold)).foregroundStyle(Palette.second)
            Text(message).font(.system(size: 14)).foregroundStyle(Palette.third)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46).padding(.horizontal, 24)
    }
}

/// En navigeringsrad: lista, livsområde eller projekt.
struct NavRow: View {
    var symbol: String? = nil
    var pie: Double? = nil
    let title: String
    let tint: Color
    var badge: Int = 0
    var indent: CGFloat = 0
    var trailing: String? = nil
    let action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 12) {
                Group {
                    if let p = pie { ProgressPie(fraction: p, tint: tint).frame(width: 19, height: 19) }
                    else if let s = symbol {
                        Image(systemName: s)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 28, height: 28)
                            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .frame(width: 28)
                Text(title)
                    .font(Typo.row)
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let t = trailing {
                    Text(t).font(Typo.meta).foregroundStyle(Palette.third).monospacedDigit()
                } else if badge > 0 {
                    Text("\(badge)").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.third).monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.third.opacity(0.6))
            }
            .padding(.leading, 14 + indent).padding(.trailing, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ProgressPie: View {
    let fraction: Double
    let tint: Color
    var body: some View {
        ZStack {
            if fraction >= 1 {
                Circle().fill(tint)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .black))
                    .foregroundStyle(Palette.card)
            } else {
                Circle().stroke(Palette.third.opacity(0.45), lineWidth: 2.4)
                Circle().trim(from: 0, to: max(0.001, fraction))
                    .stroke(tint, style: .init(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: fraction)
    }
}

/// Ett ark med uppgiftsrader, med hårfina linjer emellan.
struct TodoCard: View {
    @EnvironmentObject var store: Store
    let todos: [Todo]
    @Binding var openID: String?
    var context: TodoRowView.RowContext = .init()

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(todos.enumerated()), id: \.element.id) { i, t in
                TodoRowView(todo: t, context: context, openID: $openID)
                    .preference(key: RowOrder.self, value: [t.id])
                if i < todos.count - 1 { Hairline(inset: 41) }
            }
        }
        .sheetCard()
    }
}
