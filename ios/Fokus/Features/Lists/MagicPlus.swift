import SwiftUI

/// Things magiska plus. Ett tryck lägger en uppgift sist. Lyfter man knappen
/// och drar hamnar uppgiften där man släpper — och åt vänster i ett projekt
/// blir det en rubrik i stället.
struct MagicPlus: View {
    @EnvironmentObject var store: Store
    let route: Route?
    let frames: [String: CGRect]
    let order: [String]
    let groups: [String: CGRect]
    /// (index i S.todos, är rubrik, dag om man släppte i en dagsgrupp)
    var onCreate: (Int?, Bool, DayKey?) -> Void

    @State private var drag: CGSize = .zero
    @State private var lifted = false
    @State private var target: Target?

    private struct Target: Equatable {
        var localIndex: Int
        var line: CGRect        // var strecket ritas, i globala koordinater
        var heading: Bool
        var day: DayKey?
    }

    private var tint: Color { store.activeTint }
    private var inProject: Bool { if case .project = route { return true }; return false }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if lifted, let t = target {
                GeometryReader { _ in
                    Capsule()
                        .fill(tint)
                        .frame(width: t.heading ? 84 : t.line.width, height: t.heading ? 3 : 2)
                        .overlay(alignment: .leading) {
                            Circle().fill(tint).frame(width: 8, height: 8).offset(x: -3)
                        }
                        .position(x: t.heading ? t.line.minX + 42 : t.line.midX, y: t.line.minY)
                        .ignoresSafeArea()
                }
                .transition(.opacity)
            }

            Button {} label: {
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
            }
            .buttonStyle(.plain)
            .scaleEffect(lifted ? 1.07 : 1)
            .offset(drag)
            .overlay(alignment: .trailing) {
                if lifted, let t = target {
                    Text(hint(t))
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
        .coordinateSpace(name: "magic")
    }

    private func hint(_ t: Target) -> String {
        if t.heading { return "Ny rubrik" }
        if let d = t.day { return Sv.day(d) }
        return "Ny uppgift"
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if !lifted {
                    guard abs(v.translation.width) + abs(v.translation.height) > 8 else { return }
                    lifted = true
                    Haptics.press()
                }
                drag = v.translation
                aim(at: v.location)
            }
            .onEnded { v in
                let wasLifted = lifted
                let t = target
                lifted = false
                drag = .zero
                target = nil
                if !wasLifted {
                    onCreate(nil, false, nil)          // ett tryck: sist i listan
                } else {
                    onCreate(t.map { globalIndex($0.localIndex) }, t?.heading ?? false, t?.day)
                }
            }
    }

    private func aim(at point: CGPoint) {
        let visible = order.compactMap { id -> (String, CGRect)? in frames[id].map { (id, $0) } }
        let heading = inProject && point.x < 84

        guard !visible.isEmpty else {
            if target != nil { target = nil }
            return
        }
        let idx = visible.filter { point.y > $0.1.midY }.count
        let ref = visible[min(idx, visible.count - 1)].1
        let below = idx >= visible.count
        let line = CGRect(x: ref.minX + 12,
                          y: below ? ref.maxY : ref.minY,
                          width: ref.width - 24, height: 2)
        let day = groups.first { $0.value.contains(CGPoint(x: $0.value.midX, y: point.y)) }
            .flatMap { DayKey(raw: $0.key) }

        let next = Target(localIndex: idx, line: line, heading: heading, day: day)
        if next != target {
            Haptics.tick()
            target = next
        }
    }

    /// Positionen i S.todos är ordningen — översätt listans index dit.
    private func globalIndex(_ local: Int) -> Int {
        let visible = order.filter { frames[$0] != nil }
        guard !visible.isEmpty else { return store.s.todos.count }
        if local >= visible.count {
            if let last = store.index(of: visible[visible.count - 1]) { return last + 1 }
            return store.s.todos.count
        }
        return store.index(of: visible[local]) ?? store.s.todos.count
    }
}
