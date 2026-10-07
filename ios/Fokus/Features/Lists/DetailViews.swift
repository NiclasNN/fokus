import SwiftUI

// MARK: - Delade småsaker

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
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// En rad som leder någon annanstans — lista, livsområde eller projekt.
struct NavRowLabel: View {
    var symbol: String? = nil
    let title: String
    let tint: Color
    var badge: Int = 0
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let s = symbol {
                Image(systemName: s)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text(title).font(Typo.row).foregroundStyle(Palette.label).lineLimit(1)
            Spacer(minLength: 6)
            if let t = trailing {
                Text(t).font(Typo.meta).foregroundStyle(Palette.third).monospacedDigit()
            } else if badge > 0 {
                Text("\(badge)").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.third).monospacedDigit()
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - En smart lista

struct SmartListView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: ListUI
    let list: SmartList
    @State private var query = ""

    var body: some View {
        List {
            let todos = filtered(store.items(in: list))

            if list == .today && !todos.isEmpty { planHeader }

            if todos.isEmpty {
                EmptyNote(title: query.isEmpty ? list.empty.0 : "Ingen träff",
                          body: query.isEmpty ? list.empty.1 : "Inget som heter ”\(query)” i \(list.title).")
            } else {
                switch list {
                case .upcoming: dayGroups(todos) { $0.when?.day }
                case .logbook:  dayGroups(todos, newestFirst: true) { $0.completedAt.map(DayKey.init) }
                case .today:    todaySplit(todos)
                default:        Section { ForEach(todos) { row($0) } }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.large)
        // Things: dra ner i en lista för att söka
        .searchable(text: $query, prompt: "Sök i \(list.title)")
        .toolbar {
            if list.countsBadge {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(store.count(list))")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.third).monospacedDigit()
                }
            }
        }
    }

    private func filtered(_ items: [Todo]) -> [Todo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(q) || $0.notes.lowercased().contains(q)
                || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    /// Dagens plan — listan vet hur mycket tid den är värd.
    private var planHeader: some View {
        let plan = store.todayPlan()
        return HStack(spacing: 6) {
            Image(systemName: "timer").font(.system(size: 11, weight: .semibold))
            Text("\(Sv.duration(seconds: plan.planned)) planerat")
            if plan.done > 0 {
                Text("·").foregroundStyle(Palette.third)
                Text("\(Sv.duration(seconds: plan.done)) fokuserat idag")
                    .foregroundStyle(Palette.anytime)
            }
            Spacer()
        }
        .font(Typo.meta)
        .foregroundStyle(Palette.second)
        .padding(.horizontal, 16).padding(.bottom, 4)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder private func row(_ t: Todo) -> some View {
        TodoRowView(todo: t, context: ctx).todoRow(t)
    }

    private var ctx: TodoRowView.RowContext {
        var c = TodoRowView.RowContext()
        if list == .today || list == .upcoming { c.hideWhen = true }
        return c
    }

    /// I kväll är en egen sektion under Idag, med månen som märke.
    @ViewBuilder private func todaySplit(_ todos: [Todo]) -> some View {
        let day = todos.filter { !$0.evening }
        let eve = todos.filter { $0.evening }
        if !day.isEmpty { Section { ForEach(day) { row($0) } } }
        if !eve.isEmpty {
            Section {
                ForEach(eve) { row($0) }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill").font(.system(size: 11, weight: .semibold))
                    Text("I kväll").font(Typo.section).kerning(0.6)
                }
                .foregroundStyle(Palette.evening)
                .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private func dayGroups(_ todos: [Todo], newestFirst: Bool = false,
                           by key: (Todo) -> DayKey?) -> some View {
        let grouped = Dictionary(grouping: todos.compactMap { t -> (DayKey, Todo)? in
            key(t).map { ($0, t) }
        }, by: \.0).mapValues { $0.map(\.1) }
        let keys = newestFirst ? grouped.keys.sorted(by: >) : grouped.keys.sorted()

        ForEach(keys, id: \.self) { k in
            Section {
                ForEach(grouped[k] ?? []) { row($0) }
            } header: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Sv.day(k))
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(k == DayKey.today ? list.tint : Palette.label)
                    Text(Sv.daySubtitle(k)).font(Typo.meta).foregroundStyle(Palette.third)
                }
                .textCase(nil)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: GroupFrames.self, value: [k.raw: g.frame(in: .global)])
                    }
                )
            }
        }
    }
}

// MARK: - Ett livsområde

struct AreaView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: ListUI
    let area: AreaID

    var body: some View {
        let a = Area.of(area)
        List {
            let loose = store.looseTodos(in: area)
            let someday = store.somedayTodos(in: area)

            if loose.isEmpty && someday.isEmpty {
                EmptyNote(title: "Tomt här", body: "Lägg det du vill lägga tid på i \(a?.name ?? "").")
            } else if !loose.isEmpty {
                Section {
                    ForEach(loose) { TodoRowView(todo: $0, context: ctx).todoRow($0) }
                } footer: {
                    let focused = store.focusedSeconds(inArea: area)
                    if focused > 0 {
                        Text("\(Sv.duration(seconds: focused)) fokuserat i \(a?.name ?? "") totalt")
                            .font(Typo.meta).foregroundStyle(Palette.third)
                    }
                }
            }
            if !someday.isEmpty {
                Section("Någon gång") {
                    ForEach(someday) { TodoRowView(todo: $0, context: ctx).todoRow($0) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle(a?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
    }
    private var ctx: TodoRowView.RowContext {
        var c = TodoRowView.RowContext(); c.hideArea = true; return c
    }
}
