import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var launcher = FocusLauncher.shared
    @State private var tab = Tab.lists

    enum Tab: Hashable { case focus, lists, stats, more }

    var body: some View {
        TabView(selection: $tab) {
            FocusView()
                .tabItem { Label("Fokus", systemImage: "circle.circle") }
                .tag(Tab.focus)
            ListsHomeView()
                .tabItem { Label("Listor", systemImage: "list.bullet") }
                .tag(Tab.lists)
            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.bar") }
                .tag(Tab.stats)
            SettingsView()
                .tabItem { Label("Mer", systemImage: "gearshape") }
                .tag(Tab.more)
        }
        .onChange(of: tab) { _, _ in Haptics.tap() }
        // ▶ på en rad laddar uppgiften i ratten — och tar dig dit.
        .onChange(of: launcher.jumpToFocus) { _, go in
            guard go else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { tab = .focus }
            launcher.jumpToFocus = false
        }
        // Ett avslutat pass är inte samma sak som en avbockad uppgift.
        // Appen frågar i stället för att anta.
        .alert("Passet är klart", isPresented: finishedBinding) {
            Button("Bocka av") {
                if let id = store.finishedTodoID {
                    Sound.shared.check(); Haptics.success()
                    withAnimation { store.setDone(id, true) }
                }
                store.finishedTodoID = nil
            }
            Button("Inte klar än", role: .cancel) { store.finishedTodoID = nil }
        } message: {
            Text("\(store.todo(store.finishedTodoID)?.title ?? "Uppgiften") — vill du bocka av den?")
        }
        // Ett pågående pass följer med till alla flikar.
        .safeAreaInset(edge: .top) {
            if store.s.timer.isLive && tab != .focus {
                // Egen ogenomskinlig yta: annars lyser navigationsfältets
                // eget underlag igenom runt pillret.
                RunningPill { tab = .focus }
                    .frame(maxWidth: .infinity)
                    .background(Palette.bg)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.s.timer.isLive)
    }
}

extension RootView {
    var finishedBinding: Binding<Bool> {
        Binding(get: { store.finishedTodoID != nil },
                set: { if !$0 { store.finishedTodoID = nil } })
    }
}

/// Samma sanning på alla flikar — läses ur samma `remaining`.
private struct RunningPill: View {
    @EnvironmentObject var store: Store
    var onTap: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); onTap() }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Area.of(store.s.timer.areaID)?.tint ?? Palette.blue)
                    .frame(width: 7, height: 7)
                    .opacity(store.s.timer.status == .running ? 1 : 0.45)
                Text(Sv.clock(store.s.timer.remaining))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                Text(store.sessionTitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.second)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.third)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Palette.hair, lineWidth: 0.5))
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }
}
