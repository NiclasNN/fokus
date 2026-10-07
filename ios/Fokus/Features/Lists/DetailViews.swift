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

/// En rad som leder någon annanstans — lista, livsområde eller projekt.
struct NavRowLabel: View {
    var symbol: String? = nil
    var pie: Double? = nil
    let title: String
    let tint: Color
    var badge: Int = 0
    var trailing: String? = nil

    var body: some View {
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
            let projects = store.projects(in: list)

            if list == .today && (!todos.isEmpty || !projects.isEmpty) { planHeader }

            if todos.isEmpty && projects.isEmpty {
                EmptyNote(title: query.isEmpty ? list.empty.0 : "Ingen träff",
                          body: query.isEmpty ? list.empty.1 : "Inget som heter ”\(query)” i \(list.title).")
            } else {
                if !projects.isEmpty {
                    Section { ForEach(projects) { projectLink($0) } }
                }
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

    @ViewBuilder private func projectLink(_ p: Project) -> some View {
        let pr = store.progress(p.id)
        NavigationLink(value: Route.project(p.id)) {
            NavRowLabel(pie: pr.total == 0 ? 0 : Double(pr.done) / Double(pr.total),
                        title: p.title, tint: Area.of(p.areaID)?.tint ?? Palette.inbox,
                        trailing: pr.total > 0 ? "\(pr.done)/\(pr.total)" : nil)
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Palette.hair)
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
    @State private var newProject = false

    var body: some View {
        let a = Area.of(area)
        List {
            Section {
                ForEach(store.projects(in: area)) { p in
                    let pr = store.progress(p.id)
                    NavigationLink(value: Route.project(p.id)) {
                        NavRowLabel(pie: pr.total == 0 ? 0 : Double(pr.done) / Double(pr.total),
                                    title: p.title, tint: a?.tint ?? Palette.inbox,
                                    trailing: pr.total > 0 ? "\(pr.done)/\(pr.total)" : nil)
                    }
                    .listRowSeparatorTint(Palette.hair)
                }
                Button { Haptics.tap(); newProject = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(a?.tint ?? Palette.blue)
                            .frame(width: 28, height: 28)
                            .background((a?.tint ?? Palette.blue).opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("Nytt projekt").font(Typo.row).foregroundStyle(a?.tint ?? Palette.blue)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            } footer: {
                let focused = store.focusedSeconds(inArea: area)
                if focused > 0 {
                    Text("\(Sv.duration(seconds: focused)) fokuserat i \(a?.name ?? "") totalt")
                        .font(Typo.meta).foregroundStyle(Palette.third)
                }
            }

            let loose = store.looseTodos(in: area)
            let someday = store.somedayTodos(in: area)

            if !loose.isEmpty {
                Section("Uppgifter") {
                    ForEach(loose) { TodoRowView(todo: $0, context: ctx).todoRow($0) }
                }
            } else if store.projects(in: area).isEmpty {
                EmptyNote(title: "Tomt här", body: "Lägg det du vill lägga tid på i \(a?.name ?? "").")
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
        .sheet(isPresented: $newProject) {
            NewProjectSheet(area: area) { _ in }.environmentObject(store)
        }
    }
    private var ctx: TodoRowView.RowContext {
        var c = TodoRowView.RowContext(); c.hideArea = true; return c
    }
}

// MARK: - Ett projekt

struct ProjectDetailView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: ListUI
    let projectID: String
    @State private var confirmDelete = false
    @State private var whenSheet = false
    @Environment(\.dismiss) private var dismiss

    private var project: Project? { store.project(projectID) }

    var body: some View {
        let col = Area.of(project?.areaID)?.tint ?? Palette.inbox
        let pr = store.progress(projectID)

        List {
            Section {
                TextField("Anteckningar om projektet", text: notesBinding, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.second)
                    .lineLimit(1...6)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                HStack(spacing: 10) {
                    ProgressPie(fraction: pr.total == 0 ? 0 : Double(pr.done) / Double(pr.total), tint: col)
                        .frame(width: 20, height: 20)
                    Text(pr.total > 0 ? "\(pr.done) av \(pr.total) klara" : "Inga steg ännu")
                        .font(Typo.meta).foregroundStyle(Palette.second)
                    if store.focusedSeconds(inProject: projectID) > 0 {
                        Text("· \(Sv.duration(seconds: store.focusedSeconds(inProject: projectID))) fokuserat")
                            .font(Typo.meta).foregroundStyle(col)
                    }
                    Spacer()
                }
                .textCase(nil)
            }

            let rows = store.rows(inProject: projectID)
            if rows.isEmpty {
                EmptyNote(title: "Inga steg ännu",
                          body: "Tryck på plusset — dra det åt vänster för en rubrik.")
            } else {
                Section {
                    ForEach(rows) { t in
                        if t.isHeading {
                            HeadingRow(todo: store.binding(for: t.id)) { store.delete(t.id) }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .preference(key: RowOrder.self, value: [t.id])
                        } else {
                            TodoRowView(todo: t, context: projCtx)
                                .todoRow(t)
                                .preference(key: RowOrder.self, value: [t.id])
                        }
                    }
                }
            }

            let done = store.doneRows(inProject: projectID)
            if !done.isEmpty {
                Section("Klart (\(done.count))") {
                    ForEach(done.prefix(40)) { TodoRowView(todo: $0, context: projCtx).todoRow($0) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle(project?.title ?? "Projekt")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { whenSheet = true } label: { Label("Planera projektet", systemImage: "calendar") }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Ta bort projektet", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Ta bort projektet?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Ta bort projekt och uppgifter", role: .destructive) {
                store.deleteProject(projectID); dismiss()
            }
            Button("Avbryt", role: .cancel) {}
        }
        .sheet(isPresented: $whenSheet) {
            if let p = project {
                WhenSheet(when: Binding(get: { p.when },
                                        set: { var q = p; q.when = $0; store.update(q) }),
                          evening: .constant(false))
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var notesBinding: Binding<String> {
        Binding(get: { store.project(projectID)?.notes ?? "" },
                set: { v in guard var p = store.project(projectID) else { return }; p.notes = v; store.update(p) })
    }
    private var projCtx: TodoRowView.RowContext {
        var c = TodoRowView.RowContext(); c.hideProject = true; c.hideArea = true; return c
    }
}

struct HeadingRow: View {
    @Binding var todo: Todo
    var onDelete: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            TextField("Rubrik", text: $todo.title)
                .font(Typo.heading).kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Palette.second)
            Button { Haptics.tap(); onDelete() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.third)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18).padding(.bottom, 7)
        .overlay(alignment: .bottom) { Hairline().padding(.horizontal, 16) }
    }
}
