import SwiftUI

enum Route: Hashable {
    case list(SmartList)
    case area(AreaID)
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
    @StateObject private var ui = ListUI()
    @ObservedObject private var launcher = FocusLauncher.shared

    @State private var path: [Route] = []
    @State private var query = ""
    @State private var frames: [String: CGRect] = [:]
    @State private var order: [String] = []
    @State private var groups: [String: CGRect] = [:]

    private var route: Route? { path.last }

    var body: some View {
        NavigationStack(path: $path) {
            home
                .navigationDestination(for: Route.self) { r in
                    switch r {
                    case .list(let l):    SmartListView(list: l)
                    case .area(let a):    AreaView(area: a)
                    }
                }
        }
        .environmentObject(ui)
        .onPreferenceChange(RowFrames.self)   { frames = $0 }
        .onPreferenceChange(RowOrder.self)    { order = $0 }
        .onPreferenceChange(GroupFrames.self) { groups = $0 }
        // Things: ett tryck utanför kortet stänger det. Fångaren lämnar en
        // lucka där kortet står, så andra rader går att öppna med ETT tryck.
        .overlay {
            if let id = ui.openID, let f = frames[id] {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(0, f.minY))
                        .contentShape(Rectangle()).onTapGesture { closeCard() }
                    Spacer().frame(height: f.height)
                    Color.clear.frame(maxHeight: .infinity)
                        .contentShape(Rectangle()).onTapGesture { closeCard() }
                }
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !ui.selecting {
                MagicPlus(route: route, frames: frames, order: order, groups: groups) { index, day in
                    create(at: index, day: day)
                }
                .padding(.trailing, 18).padding(.bottom, 14)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if ui.selecting { SelectionBar().environmentObject(ui) }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: ui.selecting)
        .sheet(item: Binding(get: { ui.whenTarget.map(Ident.init) },
                             set: { if $0 == nil { ui.whenTarget = nil } })) { w in
            WhenSheet(when: store.binding(for: w.id).when, evening: store.binding(for: w.id).evening)
                .presentationDetents([.medium, .large]).environmentObject(store)
        }
        .sheet(item: Binding(get: { ui.moveTarget.map(Ident.init) },
                             set: { if $0 == nil { ui.moveTarget = nil } })) { w in
            MoveSheet(todo: store.binding(for: w.id), forFocus: false)
                .presentationDetents([.medium, .large]).environmentObject(store)
        }
        .sheet(item: Binding(get: { ui.repeatTarget.map(Ident.init) },
                             set: { if $0 == nil { ui.repeatTarget = nil } })) { w in
            RepeatSheet(rule: store.binding(for: w.id).repeatRule)
                .presentationDetents([.medium]).environmentObject(store)
        }
        .sheet(item: Binding(get: { launcher.needsArea.map { Ident(id: $0.id) } },
                             set: { if $0 == nil { launcher.needsArea = nil } })) { w in
            MoveSheet(todo: store.binding(for: w.id), forFocus: true)
                .presentationDetents([.medium, .large]).environmentObject(store)
        }
    }

    // MARK: - Hemskärmen

    private var home: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    ForEach(SmartList.allCases) { l in
                        NavigationLink(value: Route.list(l)) {
                            NavRowLabel(symbol: l.symbol, title: l.title, tint: l.tint,
                                        badge: store.count(l))
                        }
                    }
                }
                Section("Livsområden") {
                    ForEach(Area.all) { a in
                        NavigationLink(value: Route.area(a.id)) {
                            NavRowLabel(symbol: a.symbol, title: a.name, tint: a.tint,
                                        badge: store.areaBadge(a.id))
                        }
                    }
                }
            } else {
                searchResults
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle("Listor")
        .searchable(text: $query, prompt: "Sök uppgifter och projekt")
    }

    @ViewBuilder private var searchResults: some View {
        let hits = store.search(query)
        if hits.isEmpty {
            EmptyNote(title: "Ingen träff",
                      body: "Inget som heter ”\(query.trimmingCharacters(in: .whitespaces))”.")
        } else {
            Section("Uppgifter") {
                ForEach(hits) { TodoRowView(todo: $0).todoRow($0) }
            }
        }
    }

    private func closeCard() {
        Haptics.tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { ui.openID = nil }
    }

    // MARK: - Nytt

    private func create(at index: Int?, day: DayKey?) {
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
        case .none:
            break                                   // hemskärmen: hamnar i Inkorgen
        }
        store.insert(t, at: index)
        Haptics.success()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { ui.openID = t.id }
    }
}

// MARK: - Markeringsläget

/// Things: svep vänster för att markera, markera fler, och gör något
/// med allihop på en gång.
struct SelectionBar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: ListUI
    @State private var when = false
    @State private var move = false

    var body: some View {
        HStack(spacing: 0) {
            action("calendar", "När") { when = true }
            action("square.stack.3d.up", "Flytta") { move = true }
            action("checkmark.circle", "Klart") {
                Sound.shared.check(); Haptics.success()
                withAnimation { ui.selection.forEach { store.setDone($0, true) } }
                ui.clearSelection()
            }
            action("trash", "Radera", destructive: true) {
                Haptics.warning()
                withAnimation { ui.selection.forEach { store.delete($0) } }
                ui.clearSelection()
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .topTrailing) {
            Button { Haptics.tap(); ui.clearSelection() } label: {
                Text("\(ui.selection.count) \(ui.selection.count == 1 ? "markerad" : "markerade") · Avbryt")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.third)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14).padding(.top, -16)
        }
        .sheet(isPresented: $when) { BulkWhenSheet().environmentObject(store).environmentObject(ui) }
        .sheet(isPresented: $move) { BulkMoveSheet().environmentObject(store).environmentObject(ui) }
    }

    private func action(_ symbol: String, _ title: String,
                        destructive: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(destructive ? Palette.deadline : Palette.blue)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressScale())
    }
}

private struct Ident: Identifiable { let id: String }
