import SwiftUI

/// Things magiska plus. Ett tryck lägger en uppgift sist i listan; lyfter man
/// knappen och drar hamnar den där man släpper.
///
/// Radernas positioner läses ur `ListUI.frames`, som raderna själva fyller i
/// utan att rita om något. Ordningen är radernas lodräta läge på skärmen.
struct MagicPlus: View {
    @EnvironmentObject var store: Store
    @ObservedObject var ui: ListUI
    let route: Route?
    /// (index i S.todos, dag om man släppte på en dag i Kommande)
    var onCreate: (Int?, DayKey?) -> Void

    @State private var drag: CGSize = .zero
    @State private var lifted = false
    @State private var target: Target?

    private struct Target: Equatable {
        var id: String          // raden strecket står vid
        var below: Bool         // efter raden i stället för före
        var line: CGRect
        var day: DayKey?
    }

    private var tint: Color { store.activeTint }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if lifted, let t = target {
                GeometryReader { _ in
                    Capsule()
                        .fill(tint)
                        .frame(width: t.line.width, height: 2)
                        .overlay(alignment: .leading) {
                            Circle().fill(tint).frame(width: 8, height: 8).offset(x: -3)
                        }
                        .position(x: t.line.midX, y: t.line.minY)
                        .ignoresSafeArea()
                }
                .transition(.opacity)
            }

            // INGEN Button här: dess egen tryckgest vann över DragGesture,
            // så ett vanligt tryck skapade ingenting. Gesten äger knappen.
            Image(systemName: "plus")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(colors: [tint.opacity(0.88), tint],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .shadow(color: tint.opacity(0.45), radius: lifted ? 20 : 12, y: 6)
                .contentShape(Circle())
                .scaleEffect(lifted ? 1.07 : 1)
                .offset(drag)
                .overlay(alignment: .trailing) {
                    if lifted {
                        Text(hint)
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .fixedSize()
                            .offset(x: -66 + drag.width, y: drag.height)
                            .transition(.opacity)
                    }
                }
                .gesture(gesture)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: lifted)
    }

    private var hint: String {
        if let d = target?.day { return Sv.day(d) }
        return "Ny uppgift"
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if !lifted {
                    guard abs(v.translation.width) + abs(v.translation.height) > 8 else { return }
                    lifted = true
                    ui.openID = nil
                    Haptics.press()
                }
                drag = v.translation
                aim(at: v.location)
            }
            .onEnded { _ in
                let wasLifted = lifted
                let t = target
                lifted = false
                drag = .zero
                target = nil
                Haptics.press()
                if !wasLifted || t == nil {
                    onCreate(nil, nil)                 // ett tryck: sist i listan
                } else if let t {
                    onCreate(globalIndex(t), t.day)
                }
            }
    }

    /// Raderna som syns just nu, uppifrån och ner.
    private var visibleRows: [(id: String, frame: CGRect)] {
        let screen = UIScreen.main.bounds
        return ui.frames
            .filter { id, f in f.height > 1 && f.intersects(screen) && store.todo(id) != nil }
            .map { (id: $0.key, frame: $0.value) }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    private func aim(at point: CGPoint) {
        let rows = visibleRows
        guard !rows.isEmpty else { if target != nil { target = nil }; return }
        let idx = rows.filter { point.y > $0.frame.midY }.count
        let below = idx >= rows.count
        let ref = rows[min(idx, rows.count - 1)]
        let line = CGRect(x: ref.frame.minX + 12, y: below ? ref.frame.maxY : ref.frame.minY,
                          width: ref.frame.width - 24, height: 2)
        // I Kommande ärver den nya uppgiften dagen från raden den hamnar vid.
        var day: DayKey?
        if case .list(.upcoming)? = route { day = store.todo(ref.id)?.when?.day }
        let next = Target(id: ref.id, below: below, line: line, day: day)
        if next != target { Haptics.tick(); target = next }
    }

    /// Positionen i S.todos är ordningen — översätt släpppunkten dit.
    private func globalIndex(_ t: Target) -> Int? {
        guard let i = store.index(of: t.id) else { return nil }
        return t.below ? i + 1 : i
    }
}
