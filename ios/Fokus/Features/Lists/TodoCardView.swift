import SwiftUI

/// Raden vecklar ut sig till "ett rent vitt pappersark". Fälten ligger
/// undanstoppade som piller tills man behöver dem — Things princip.
struct TodoCardView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: ListUI
    @Binding var todo: Todo

    @State private var sheet: Sheet?
    @FocusState private var focusedCheck: String?

    enum Sheet: Identifiable {
        case when, deadline, tags, move, duration, repeating
        var id: String { String(describing: self) }
    }

    private var tint: Color { store.tint(for: todo) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            TextField("Anteckningar", text: $todo.notes, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(Palette.second)
                .lineLimit(1...8)

            if !todo.checklist.isEmpty { checklist }

            Button {
                Haptics.tap()
                let item = ChecklistItem()
                todo.checklist.append(item)
                focusedCheck = item.id
            } label: {
                Label("Lägg till steg", systemImage: "plus")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Palette.second)
            }
            .buttonStyle(.plain)

            pills
        }
        .sheet(item: $sheet) { which in
            Group {
                switch which {
                case .when:     WhenSheet(when: $todo.when, evening: $todo.evening)
                case .deadline: DeadlineSheet(deadline: $todo.deadline)
                case .tags:     TagSheet(tags: $todo.tags)
                case .move:     MoveSheet(todo: $todo, forFocus: false)
                case .duration: DurationSheet(minutes: $todo.durationMinutes)
                case .repeating: RepeatSheet(rule: $todo.repeatRule)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environmentObject(store)
        }
    }

    // MARK: - Checklistan

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach($todo.checklist) { $item in
                HStack(spacing: 9) {
                    Button {
                        Haptics.tap()
                        if !item.done { Sound.shared.check() }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { item.done.toggle() }
                    } label: {
                        CheckCircle(done: item.done, tint: tint, size: 17)
                    }
                    .buttonStyle(.plain)

                    TextField("Steg", text: $item.title)
                        .font(.system(size: 14))
                        .foregroundStyle(item.done ? Palette.third : Palette.second)
                        .strikethrough(item.done, color: Palette.third)
                        .focused($focusedCheck, equals: item.id)
                        .submitLabel(.next)
                        .onSubmit {
                            // Enter skapar nästa steg, som i Things
                            let new = ChecklistItem()
                            if let i = todo.checklist.firstIndex(where: { $0.id == item.id }) {
                                todo.checklist.insert(new, at: i + 1)
                            } else { todo.checklist.append(new) }
                            focusedCheck = new.id
                        }

                    Button {
                        Haptics.tap()
                        todo.checklist.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.third)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Pillren

    private var pills: some View {
        FlowLayout(spacing: 6) {
            pill(whenLabel, "calendar", set: todo.when != nil) { sheet = .when }
            pill(todo.deadline.map(Sv.day) ?? "Deadline", "flag",
                 set: todo.deadline != nil, color: Palette.deadline) { sheet = .deadline }
            pill(todo.tags.isEmpty ? "Taggar" : todo.tags.joined(separator: ", "), "tag",
                 set: !todo.tags.isEmpty) { sheet = .tags }
            pill(whereLabel, "square.stack.3d.up", set: todo.isFiled) { sheet = .move }
            pill(todo.repeatRule?.label ?? "Upprepa", "repeat",
                 set: todo.repeatRule != nil) { sheet = .repeating }
            pill(focusLabel, "clock", set: todo.focusedSeconds > 0) { sheet = .duration }
            pill(nil, "trash", set: false, color: Palette.deadline, plain: true) {
                ui.openID = nil
                store.delete(todo.id)
                Haptics.warning()
            }
        }
    }

    private var whenLabel: String {
        switch todo.when {
        case .someday:      return "Någon gång"
        case .on(let k):    return todo.evening && k == DayKey.today ? "I kväll" : Sv.day(k)
        case .none:         return "När"
        }
    }
    /// Appens två halvor i en rad text: planerad längd, och vad den
    /// faktiskt har kostat hittills.
    private var focusLabel: String {
        guard todo.focusedSeconds > 0 else { return "\(todo.durationMinutes) min per pass" }
        let pass = todo.sessionCount == 1 ? "pass" : "pass"
        return "\(Sv.short(seconds: todo.focusedSeconds)) · \(todo.sessionCount) \(pass)"
    }
    private var whereLabel: String {
        if let p = store.project(todo.projectID) { return p.title }
        if let a = Area.of(todo.areaID) { return a.short }
        return "Lägg i…"
    }

    private func pill(_ text: String?, _ symbol: String, set: Bool,
                      color: Color? = nil, plain: Bool = false,
                      action: @escaping () -> Void) -> some View {
        let c = color ?? tint
        return Button { Haptics.tap(); action() } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                if let t = text { Text(t).lineLimit(1) }
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(set ? c : (plain ? Palette.third : Palette.second))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(plain ? AnyShapeStyle(Color.clear)
                        : set ? AnyShapeStyle(c.opacity(0.12)) : AnyShapeStyle(Palette.sunk),
                        in: Capsule())
            .overlay(Capsule().stroke(set ? c.opacity(0.4) : .clear, lineWidth: 0.7))
        }
        .buttonStyle(PressScale())
    }
}

/// Pillren ska radbrytas som text, inte skäras av. SwiftUI har ingen
/// inbyggd flödeslayout före iOS 16-stilen nedan.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += lineH + spacing; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}
