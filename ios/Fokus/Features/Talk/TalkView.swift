import SwiftUI

/// Tala in allt du behöver göra. Appen delar upp det, sorterar varje sak i
/// rätt livsområde och uppskattar tiden. Du granskar och rättar innan
/// något sparas — sorteringen ska vara rätt, inte bara snabb.
struct TalkView: View {
    @EnvironmentObject var store: Store
    let active: Bool
    var showLists: () -> Void

    @StateObject private var dictation = Dictation()
    @State private var phase: Phase = .capture
    @State private var drafts: [DraftTask] = []
    @State private var engine: BrainDump.Engine = .simple
    @State private var step = (done: 0, total: 0)
    @State private var added: [AreaID: Int] = [:]
    @FocusState private var editing: Bool

    enum Phase { case capture, sorting, review, done }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .capture: capture
                case .sorting: sorting
                case .review:  review
                case .done:    done
                }
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Tala in")
            .animation(.spring(response: 0.38, dampingFraction: 0.88), value: phase)
        }
        .onChange(of: active) { _, on in
            if on { autoStart() } else { dictation.stop() }
        }
        .onAppear { if active { autoStart() } }
    }

    private func autoStart() {
        guard phase == .capture, dictation.transcript.isEmpty, !dictation.listening else { return }
        Task { await dictation.start() }
    }

    // MARK: - Prata

    private var capture: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Berätta allt du behöver göra, som det kommer. Appen delar upp det, lägger varje sak i rätt område och uppskattar tiden.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Palette.second)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ZStack(alignment: .topLeading) {
                    if dictation.transcript.isEmpty {
                        Text("Till exempel: ring mamma ikväll, betala elräkningen, städa badrummet och gymmet imorgon en timme…")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.third)
                            .padding(.horizontal, 5).padding(.vertical, 8)
                    }
                    TextEditor(text: $dictation.transcript)
                        .font(.system(size: 16))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 170)
                        .focused($editing)
                }
                .padding(12)
                .sheetCard()

                micButton

                if let p = dictation.problem {
                    Text(p).font(.system(size: 13)).foregroundStyle(Palette.deadline)
                        .multilineTextAlignment(.center)
                }

                Button(action: sort) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold))
                        Text("Sortera").font(.system(size: 16.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.blue, in: Capsule())
                }
                .buttonStyle(PressScale())
                .disabled(dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)

                engineNote
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var micButton: some View {
        Button {
            editing = false
            if dictation.listening { dictation.stop() } else { Task { await dictation.start() } }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(dictation.listening ? Palette.deadline : Palette.blue)
                        .frame(width: 78, height: 78)
                        .shadow(color: (dictation.listening ? Palette.deadline : Palette.blue).opacity(0.4),
                                radius: 16, y: 6)
                    if dictation.listening {
                        Circle()
                            .stroke(Palette.deadline.opacity(0.35), lineWidth: 3)
                            .frame(width: 96, height: 96)
                            .phaseAnimator([1.0, 1.12]) { v, s in v.scaleEffect(s).opacity(2 - s) }
                                animation: { _ in .easeInOut(duration: 0.9) }
                    }
                    Image(systemName: dictation.listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(height: 100)
                Text(dictation.listening ? "Lyssnar — tryck när du är klar" : "Tryck och prata")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.second)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var engineNote: some View {
        if BrainDump.onDeviceReady {
            Label("Sorteras på telefonen med Apple Intelligence. Inget lämnar enheten.",
                  systemImage: "apple.intelligence")
                .font(.system(size: 12)).foregroundStyle(Palette.third)
        } else {
            VStack(spacing: 3) {
                Text("Enkel sortering — inget lämnar enheten.")
                if let n = BrainDump.onDeviceNote { Text(n) }
            }
            .font(.system(size: 12)).foregroundStyle(Palette.third)
            .multilineTextAlignment(.center)
        }
    }

    private func sort() {
        dictation.stop()
        editing = false
        let text = dictation.transcript
        let examples = store.sortExamples
        phase = .sorting
        step = (0, 0)
        Task {
            let result = await BrainDump.parse(text, examples: examples) { done, total in
                step = (done, total)
            }
            drafts = result.tasks
            engine = result.engine
            Haptics.success()
            phase = drafts.isEmpty ? .capture : .review
            if drafts.isEmpty { dictation.problem = "Hittade inga uppgifter i texten. Prova att säga det igen." }
        }
    }

    // MARK: - Sorterar

    private var sorting: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(step.total > 0 ? "Sorterar \(step.done) av \(step.total)…" : "Delar upp det du sa…")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.second)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Granska

    private var review: some View {
        List {
            Section {
                ForEach($drafts) { $d in DraftRow(draft: $d) }
                    .onDelete { drafts.remove(atOffsets: $0); Haptics.tap() }
            } header: {
                HStack {
                    Text("\(drafts.count) \(drafts.count == 1 ? "uppgift" : "uppgifter")")
                    Spacer()
                    Text(engine == .onDevice ? "Apple Intelligence" : "Enkel sortering")
                }
                .textCase(nil)
            } footer: {
                Text("Tryck på ett område för att flytta en uppgift. Det du rättar lär appen hur du sorterar till nästa gång.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(action: commit) {
                    Text("Lägg till \(drafts.count) \(drafts.count == 1 ? "uppgift" : "uppgifter")")
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Palette.blue, in: Capsule())
                }
                .buttonStyle(PressScale())
                .disabled(drafts.isEmpty)
                Button("Ändra det jag sa") { Haptics.tap(); phase = .capture }
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func commit() {
        var counts: [AreaID: Int] = [:]
        for d in drafts where !d.title.trimmingCharacters(in: .whitespaces).isEmpty {
            store.insert(d.todo(), at: nil)
            counts[d.area, default: 0] += 1
        }
        store.saveNow()
        Sound.shared.check(); Haptics.success()
        added = counts
        drafts = []
        dictation.transcript = ""
        phase = .done
    }

    // MARK: - Klart

    private var done: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 62))
                .foregroundStyle(Palette.anytime)
                .symbolEffect(.bounce, value: phase)
            Text("\(added.values.reduce(0, +)) uppgifter tillagda")
                .font(.system(size: 22, weight: .semibold))
            VStack(spacing: 8) {
                ForEach(Area.all.filter { (added[$0.id] ?? 0) > 0 }) { a in
                    HStack(spacing: 10) {
                        Image(systemName: a.symbol).foregroundStyle(a.tint).frame(width: 22)
                        Text(a.name)
                        Spacer()
                        Text("\(added[a.id] ?? 0)").foregroundStyle(Palette.second).monospacedDigit()
                    }
                    .font(.system(size: 15.5))
                }
            }
            .padding(16)
            .sheetCard()
            .padding(.horizontal, 24)
            Spacer()
            VStack(spacing: 10) {
                Button { Haptics.tap(); phase = .capture; showLists() } label: {
                    Text("Visa i Listor")
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Palette.blue, in: Capsule())
                }
                .buttonStyle(PressScale())
                Button("Tala in mer") {
                    Haptics.tap(); phase = .capture
                    Task { await dictation.start() }
                }
                .font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
    }
}

/// En uppgift i granskningen. Området är fyra knappar — att rätta en
/// felsortering ska kosta ett tryck, inte en meny.
private struct DraftRow: View {
    @Binding var draft: DraftTask
    private let durations = [5, 10, 15, 20, 25, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Uppgift", text: $draft.title, axis: .vertical)
                .font(.system(size: 16, weight: .medium))

            HStack(spacing: 6) {
                ForEach(Area.all) { a in
                    let on = draft.area == a.id
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { draft.area = a.id }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: a.symbol).font(.system(size: 13, weight: .semibold))
                            Text(a.short).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        }
                        .foregroundStyle(on ? .white : a.tint)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(on ? AnyShapeStyle(a.tint) : AnyShapeStyle(a.tint.opacity(0.12)),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(durations, id: \.self) { m in
                        Button(m < 60 ? "\(m) min" : Sv.duration(seconds: m * 60)) { draft.minutes = m }
                    }
                } label: {
                    Label(draft.minutes < 60 ? "\(draft.minutes) min" : Sv.duration(seconds: draft.minutes * 60),
                          systemImage: "clock")
                }
                Menu {
                    ForEach(DraftTask.Day.allCases) { d in
                        Button { draft.day = d } label: { Label(d.label, systemImage: d.symbol) }
                    }
                } label: {
                    Label(draft.day.label, systemImage: draft.day.symbol)
                }
                Spacer()
            }
            .font(.system(size: 13, weight: .medium))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}
