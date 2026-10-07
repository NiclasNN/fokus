import SwiftUI

struct PickRow: View {
    let symbol: String, title: String
    var color: Color = Palette.blue
    var on: Bool = false
    var indent: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(title).font(.system(size: 16)).foregroundStyle(Palette.label)
                Spacer()
                if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(color) }
            }
            .padding(.leading, indent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - När

struct WhenSheet: View {
    @Binding var when: When?
    @Binding var evening: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PickRow(symbol: "star.fill", title: "Idag", color: Palette.today,
                            on: when?.day == DayKey.today && !evening) { set(.on(DayKey.today), false) }
                    PickRow(symbol: "moon.fill", title: "I kväll", color: Palette.evening,
                            on: when?.day == DayKey.today && evening) { set(.on(DayKey.today), true) }
                    PickRow(symbol: "calendar", title: "I morgon", color: Palette.upcoming,
                            on: when?.day == DayKey.today(offsetBy: 1)) { set(.on(DayKey.today(offsetBy: 1)), false) }
                    PickRow(symbol: "archivebox.fill", title: "Någon gång", color: Palette.someday,
                            on: when == .someday) { set(.someday, false) }
                    PickRow(symbol: "square.stack.3d.up.fill", title: "När som helst — ingen dag",
                            color: Palette.anytime, on: when == nil) { set(nil, false) }
                }
                Section("Eller en bestämd dag") {
                    DatePicker("Dag", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .onChange(of: date) { _, d in set(.on(DayKey(d)), false) }
                }
            }
            .navigationTitle("När ska den göras?")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { date = when?.day?.date ?? Date() }
        }
    }
    private func set(_ w: When?, _ eve: Bool) {
        when = w; evening = eve; Haptics.press(); dismiss()
    }
}

// MARK: - Deadline

struct DeadlineSheet: View {
    @Binding var deadline: DayKey?
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("En deadline är när uppgiften måste vara klar — inte när du tänkt göra den. Den som går ut tränger sig in i Idag.")
                        .font(.system(size: 13.5)).foregroundStyle(Palette.second)
                }
                Section {
                    PickRow(symbol: "flag.fill", title: "Idag", color: Palette.deadline) { set(DayKey.today) }
                    PickRow(symbol: "flag.fill", title: "I morgon", color: Palette.upcoming) { set(DayKey.today(offsetBy: 1)) }
                    PickRow(symbol: "flag.fill", title: "Om en vecka", color: Palette.today) { set(DayKey.today(offsetBy: 7)) }
                    PickRow(symbol: "xmark", title: "Ingen deadline", color: Palette.anytime,
                            on: deadline == nil) { set(nil) }
                }
                Section("Eller ett datum") {
                    DatePicker("Dag", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .onChange(of: date) { _, d in set(DayKey(d)) }
                }
            }
            .navigationTitle("Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { date = deadline?.date ?? Date() }
        }
    }
    private func set(_ k: DayKey?) { deadline = k; Haptics.press(); dismiss() }
}

// MARK: - Taggar

struct TagSheet: View {
    @EnvironmentObject var store: Store
    @Binding var tags: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var fresh = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Ny tagg", text: $fresh)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button(action: add) { Image(systemName: "plus.circle.fill") }
                            .disabled(fresh.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if !store.allTags.isEmpty {
                    Section("Använda taggar") {
                        ForEach(store.allTags, id: \.self) { t in
                            PickRow(symbol: "tag", title: t, color: Palette.second,
                                    on: tags.contains(t)) { toggle(t) }
                        }
                    }
                }
            }
            .navigationTitle("Taggar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klar") { dismiss() } } }
        }
    }
    private func add() {
        let v = fresh.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        if !tags.contains(v) { tags.append(v) }
        fresh = ""; Haptics.tap()
    }
    private func toggle(_ t: String) {
        if let i = tags.firstIndex(of: t) { tags.remove(at: i) } else { tags.append(t) }
    }
}

// MARK: - Plats

struct MoveSheet: View {
    @EnvironmentObject var store: Store
    @Binding var todo: Todo
    var forFocus: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if forFocus {
                    Section {
                        Text("Passet bokförs på området du väljer. Du kan flytta uppgiften igen när som helst.")
                            .font(.system(size: 13.5)).foregroundStyle(Palette.second)
                    }
                }
                Section {
                    if !forFocus {
                        PickRow(symbol: "tray", title: "Inkorgen", color: Palette.inbox,
                                on: !todo.isFiled) { place(nil, nil) }
                    }
                    ForEach(Area.all) { a in
                        PickRow(symbol: a.symbol, title: a.name, color: a.tint,
                                on: todo.areaID == a.id && todo.projectID == nil) { place(a.id, nil) }
                        ForEach(store.projects(in: a.id)) { p in
                            PickRow(symbol: "chevron.right", title: p.title, color: a.tint,
                                    on: todo.projectID == p.id, indent: 22) { place(a.id, p.id) }
                        }
                    }
                }
            }
            .navigationTitle(forFocus ? "Var ska tiden bokas?" : "Var hör den hemma?")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    private func place(_ area: AreaID?, _ project: String?) {
        todo.areaID = area
        todo.projectID = project
        Haptics.press()
        dismiss()
        if forFocus, let a = area {
            let t = todo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                FocusLauncher.shared.launch(t, area: a, store: store)
            }
        }
    }
}

// MARK: - Tid per pass

struct DurationSheet: View {
    @Binding var minutes: Int
    @Environment(\.dismiss) private var dismiss
    private let presets = [5, 10, 15, 25, 30, 45, 60, 90, 120]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Så lång blir timern när du startar den här uppgiften.")
                        .font(.system(size: 13.5)).foregroundStyle(Palette.second)
                }
                Section {
                    ForEach(presets, id: \.self) { m in
                        PickRow(symbol: "clock", title: m < 60 ? "\(m) minuter" : Sv.duration(seconds: m * 60),
                                color: Palette.blue, on: minutes == m) {
                            minutes = m; Haptics.press(); dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Tid per pass")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Nytt projekt

struct NewProjectSheet: View {
    @EnvironmentObject var store: Store
    let area: AreaID?
    var onCreate: (Project) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vad ska bli gjort?", text: $title)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(create)
                } footer: {
                    Text("Ett projekt är flera steg mot ett mål"
                         + (Area.of(area).map { " — det här hamnar i \($0.name)" } ?? "") + ".")
                }
            }
            .navigationTitle("Nytt projekt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skapa", action: create)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
    private func create() {
        let v = title.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        let p = store.addProject(v, in: area)
        Haptics.success()
        dismiss()
        onCreate(p)
    }
}

// MARK: - Upprepning

struct RepeatSheet: View {
    @Binding var rule: RepeatRule?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("När du bockar av en upprepande uppgift föds nästa på nästa datum. Räknat från den dag den var planerad — inte från idag, så ett veckoåtagande glider inte en dag varje gång du är sen.")
                        .font(.system(size: 13.5)).foregroundStyle(Palette.second)
                }
                Section {
                    PickRow(symbol: "xmark", title: "Upprepas inte", color: Palette.anytime,
                            on: rule == nil) { set(nil) }
                    ForEach(RepeatRule.allCases) { r in
                        PickRow(symbol: "repeat", title: r.label, color: Palette.blue,
                                on: rule == r) { set(r) }
                    }
                }
            }
            .navigationTitle("Upprepa")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    private func set(_ r: RepeatRule?) { rule = r; Haptics.press(); dismiss() }
}

// MARK: - Flera på en gång

struct BulkWhenSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: ListUI
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PickRow(symbol: "star.fill", title: "Idag", color: Palette.today) { set(.on(DayKey.today), false) }
                    PickRow(symbol: "moon.fill", title: "I kväll", color: Palette.evening) { set(.on(DayKey.today), true) }
                    PickRow(symbol: "calendar", title: "I morgon", color: Palette.upcoming) { set(.on(DayKey.today(offsetBy: 1)), false) }
                    PickRow(symbol: "archivebox.fill", title: "Någon gång", color: Palette.someday) { set(.someday, false) }
                    PickRow(symbol: "square.stack.3d.up.fill", title: "När som helst", color: Palette.anytime) { set(nil, false) }
                }
                Section("Eller en bestämd dag") {
                    DatePicker("Dag", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .onChange(of: date) { _, d in set(.on(DayKey(d)), false) }
                }
            }
            .navigationTitle("\(ui.selection.count) \(ui.selection.count == 1 ? "uppgift" : "uppgifter")")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    private func set(_ w: When?, _ eve: Bool) {
        for id in ui.selection {
            guard var t = store.todo(id) else { continue }
            t.when = w; t.evening = eve
            store.update(t)
        }
        Haptics.press(); ui.clearSelection(); dismiss()
    }
}

struct BulkMoveSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: ListUI
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PickRow(symbol: "tray", title: "Inkorgen", color: Palette.inbox) { place(nil, nil) }
                    ForEach(Area.all) { a in
                        PickRow(symbol: a.symbol, title: a.name, color: a.tint) { place(a.id, nil) }
                        ForEach(store.projects(in: a.id)) { p in
                            PickRow(symbol: "chevron.right", title: p.title, color: a.tint, indent: 22) {
                                place(a.id, p.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Flytta \(ui.selection.count)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    private func place(_ area: AreaID?, _ project: String?) {
        for id in ui.selection {
            guard var t = store.todo(id) else { continue }
            t.areaID = area; t.projectID = project
            store.update(t)
        }
        Haptics.press(); ui.clearSelection(); dismiss()
    }
}
