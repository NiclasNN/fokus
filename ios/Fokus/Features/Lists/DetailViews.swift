import SwiftUI

// MARK: - En smart lista

struct SmartListView: View {
    @EnvironmentObject var store: Store
    let list: SmartList
    @Binding var openID: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let todos = store.items(in: list)
                let projects = store.projects(in: list)

                if todos.isEmpty && projects.isEmpty {
                    EmptyNote(title: list.empty.0, body: list.empty.1)
                } else {
                    if !projects.isEmpty {
                        ProjectCard(projects: projects)
                        if !todos.isEmpty { Spacer().frame(height: 14) }
                    }
                    switch list {
                    case .upcoming: dayGroups(todos, by: { $0.when?.day })
                    case .logbook:  dayGroups(todos, by: { $0.completedAt.map(DayKey.init) }, newestFirst: true)
                    case .today:    todaySplit(todos)
                    default:        TodoCard(todos: todos, openID: $openID, context: ctx)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 96)
        }
        .background(Palette.bg)
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.large)
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

    private var ctx: TodoRowView.RowContext {
        var c = TodoRowView.RowContext()
        if list == .today || list == .upcoming { c.hideWhen = true }
        return c
    }

    /// I kväll är en egen sektion under Idag, med månen som märke.
    @ViewBuilder private func todaySplit(_ todos: [Todo]) -> some View {
        let day = todos.filter { !$0.evening }
        let eve = todos.filter { $0.evening }
        if !day.isEmpty { TodoCard(todos: day, openID: $openID, context: ctx) }
        if !eve.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "moon.fill").font(.system(size: 11, weight: .semibold))
                Text("I KVÄLL").font(Typo.section).kerning(0.8)
                Spacer()
            }
            .foregroundStyle(Palette.evening)
            .padding(.top, 20).padding(.bottom, 7).padding(.horizontal, 4)
            TodoCard(todos: eve, openID: $openID, context: ctx)
        }
    }

    @ViewBuilder
    private func dayGroups(_ todos: [Todo], by key: (Todo) -> DayKey?, newestFirst: Bool = false) -> some View {
        let grouped = Dictionary(grouping: todos.compactMap { t -> (DayKey, Todo)? in
            key(t).map { ($0, t) }
        }, by: \.0).mapValues { $0.map(\.1) }
        let keys = newestFirst ? grouped.keys.sorted(by: >) : grouped.keys.sorted()

        ForEach(keys, id: \.self) { k in
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Sv.day(k))
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(k == DayKey.today ? list.tint : Palette.label)
                    Text(Sv.daySubtitle(k)).font(Typo.meta).foregroundStyle(Palette.third)
                    Spacer()
                }
                .padding(.horizontal, 4)
                TodoCard(todos: grouped[k] ?? [], openID: $openID, context: ctx)
            }
            .padding(.bottom, 16)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: GroupFrames.self, value: [k.raw: g.frame(in: .global)])
                }
            )
        }
    }
}

struct ProjectCard: View {
    @EnvironmentObject var store: Store
    let projects: [Project]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(projects.enumerated()), id: \.element.id) { i, p in
                let pr = store.progress(p.id)
                NavigationLink(value: Route.project(p.id)) {
                    HStack(spacing: 12) {
                        ProgressPie(fraction: pr.total == 0 ? 0 : Double(pr.done) / Double(pr.total),
                                    tint: Area.of(p.areaID)?.tint ?? Palette.inbox)
                            .frame(width: 19, height: 19).frame(width: 28)
                        Text(p.title).font(Typo.row).foregroundStyle(Palette.label).lineLimit(1)
                        Spacer(minLength: 6)
                        if pr.total > 0 {
                            Text("\(pr.done)/\(pr.total)").font(Typo.meta)
                                .foregroundStyle(Palette.third).monospacedDigit()
                        }
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.third.opacity(0.6))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < projects.count - 1 { Hairline(inset: 54) }
            }
        }
        .sheetCard()
    }
}

// MARK: - Ett livsområde

struct AreaView: View {
    @EnvironmentObject var store: Store
    let area: AreaID
    @Binding var openID: String?
    @State private var newProject = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let projects = store.projects(in: area)
                let loose = store.looseTodos(in: area)
                let someday = store.somedayTodos(in: area)

                VStack(spacing: 0) {
                    if !projects.isEmpty {
                        ProjectCard(projects: projects)
                            .padding(.bottom, 0)
                    }
                }
                Button { Haptics.tap(); newProject = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Area.of(area)?.tint ?? Palette.blue)
                            .frame(width: 28, height: 28)
                            .background((Area.of(area)?.tint ?? Palette.blue).opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("Nytt projekt").font(Typo.row)
                            .foregroundStyle(Area.of(area)?.tint ?? Palette.blue)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sheetCard()
                .padding(.top, projects.isEmpty ? 0 : 10)

                if !loose.isEmpty {
                    SectionLabel("Uppgifter")
                    TodoCard(todos: loose, openID: $openID, context: areaCtx)
                } else if projects.isEmpty {
                    EmptyNote(title: "Tomt här",
                              body: "Lägg det du vill lägga tid på i \(Area.of(area)?.name ?? "").")
                }
                if !someday.isEmpty {
                    SectionLabel("Någon gång")
                    TodoCard(todos: someday, openID: $openID, context: areaCtx)
                }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 96)
        }
        .background(Palette.bg)
        .navigationTitle(Area.of(area)?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $newProject) {
            NewProjectSheet(area: area) { _ in }.environmentObject(store)
        }
    }
    private var areaCtx: TodoRowView.RowContext {
        var c = TodoRowView.RowContext(); c.hideArea = true; return c
    }
}

// MARK: - Ett projekt

struct ProjectDetailView: View {
    @EnvironmentObject var store: Store
    let projectID: String
    @Binding var openID: String?
    @State private var confirmDelete = false
    @State private var whenSheet = false
    @Environment(\.dismiss) private var dismiss

    private var project: Project? { store.project(projectID) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let rows = store.rows(inProject: projectID)
                let done = store.doneRows(inProject: projectID)

                if rows.isEmpty {
                    EmptyNote(title: "Inga steg ännu",
                              body: "Tryck på plusset — dra det åt vänster för en rubrik.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                            if t.isHeading {
                                HeadingRow(todo: store.binding(for: t.id)) { store.delete(t.id) }
                                    .preference(key: RowOrder.self, value: [t.id])
                            } else {
                                TodoRowView(todo: t, context: projCtx, openID: $openID)
                                    .preference(key: RowOrder.self, value: [t.id])
                                if i < rows.count - 1, !rows[i + 1].isHeading { Hairline(inset: 41) }
                            }
                        }
                    }
                    .sheetCard()
                }

                if !done.isEmpty {
                    SectionLabel("Klart (\(done.count))")
                    TodoCard(todos: Array(done.prefix(40)), openID: $openID, context: projCtx)
                }

                HStack(spacing: 8) {
                    Button { Haptics.tap(); whenSheet = true } label: {
                        Label(project?.when != nil ? "Planerat" : "Planera projektet", systemImage: "calendar")
                            .font(.system(size: 13, weight: .medium))
                    }
                    Spacer()
                    Button(role: .destructive) { Haptics.warning(); confirmDelete = true } label: {
                        Label("Ta bort", systemImage: "trash").font(.system(size: 13, weight: .medium))
                    }
                }
                .padding(.top, 20).padding(.horizontal, 4)
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 96)
        }
        .background(Palette.bg)
        .navigationTitle(project?.title ?? "Projekt")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let pr = store.progress(projectID)
                HStack(spacing: 7) {
                    ProgressPie(fraction: pr.total == 0 ? 0 : Double(pr.done) / Double(pr.total),
                                tint: Area.of(project?.areaID)?.tint ?? Palette.inbox)
                        .frame(width: 17, height: 17)
                    Text("\(pr.done)/\(pr.total)").font(Typo.meta)
                        .foregroundStyle(Palette.third).monospacedDigit()
                }
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
        .padding(.horizontal, 14)
        .padding(.top, 16).padding(.bottom, 7)
        .overlay(alignment: .bottom) { Hairline().padding(.horizontal, 14) }
    }
}
