import SwiftUI
import Combine
import UserNotifications

@MainActor
final class Store: ObservableObject {
    @Published var s = AppState()
    /// Driver nedräkningen. Bara den här ändras en gång per sekund — resten
    /// av modellen står still, så listorna ritas inte om i onödan.
    @Published private(set) var now = Date()

    private var saveTask: Task<Void, Never>?
    private var ticker: AnyCancellable?

    // MARK: - Liv

    init() {
        load()
        Haptics.enabled = s.settings.haptics
        Sound.shared.enabled = s.settings.sound
        resumeIfNeeded()
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("fokus-state.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let state = try? JSONDecoder.fokus.decode(AppState.self, from: data) else { return }
        s = state
    }
    /// Skrivningen samlas ihop — varje tangenttryck i ett kort ska inte röra disken.
    func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
    func saveNow() {
        saveTask?.cancel()
        guard let data = try? JSONEncoder.fokus.encode(s) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: - Uppslag

    func todo(_ id: String?) -> Todo? { id.flatMap { i in s.todos.first { $0.id == i } } }
    func project(_ id: String?) -> Project? { id.flatMap { i in s.projects.first { $0.id == i } } }
    func index(of id: String) -> Int? { s.todos.firstIndex { $0.id == id } }

    /// Uppgiftens färg: områdets, projektets områdes, annars inkorgsblått.
    func tint(for t: Todo) -> Color {
        if let a = Area.of(t.areaID) { return a.tint }
        if let p = project(t.projectID), let a = Area.of(p.areaID) { return a.tint }
        return Palette.inbox
    }
    /// Accenten för hela appen just nu: uppgiftens färg om ett pass har en,
    /// annars det valda områdets.
    var activeTint: Color {
        if let t = currentTodo { return tint(for: t) }
        return Area.of(s.timer.areaID)?.tint ?? Palette.blue
    }
    func area(for t: Todo) -> Area? {
        Area.of(t.areaID) ?? Area.of(project(t.projectID)?.areaID)
    }

    // MARK: - Listorna

    func items(in list: SmartList) -> [Todo] {
        if list == .logbook {
            return s.todos.filter { !$0.isHeading && $0.done }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                .prefix(200).map { $0 }
        }
        return s.todos.filter { list.contains($0) }
    }
    func projects(in list: SmartList) -> [Project] { s.projects.filter { list.contains($0) } }
    func count(_ list: SmartList) -> Int {
        guard list.countsBadge else { return 0 }
        return items(in: list).count + projects(in: list).count
    }

    func projects(in area: AreaID) -> [Project] { s.projects.filter { $0.areaID == area && !$0.done } }
    func looseTodos(in area: AreaID) -> [Todo] {
        s.todos.filter { !$0.isHeading && $0.areaID == area && $0.projectID == nil
                         && !$0.done && $0.when != .someday }
    }
    func somedayTodos(in area: AreaID) -> [Todo] {
        s.todos.filter { !$0.isHeading && $0.areaID == area && $0.projectID == nil
                         && !$0.done && $0.when == .someday }
    }
    func areaBadge(_ area: AreaID) -> Int {
        s.todos.filter { !$0.isHeading && $0.areaID == area && !$0.done && $0.when != .someday }.count
            + projects(in: area).count
    }

    /// Rubriker och uppgifter i arrayordning — ordningen ÄR sorteringen.
    func rows(inProject id: String) -> [Todo] {
        s.todos.filter { $0.projectID == id && ($0.isHeading || !$0.done) }
    }
    func doneRows(inProject id: String) -> [Todo] {
        s.todos.filter { !$0.isHeading && $0.projectID == id && $0.done }
    }
    func progress(_ projectID: String) -> (done: Int, total: Int) {
        let all = s.todos.filter { !$0.isHeading && $0.projectID == projectID }
        return (all.filter(\.done).count, all.count)
    }
    var allTags: [String] { Array(Set(s.todos.flatMap(\.tags))).sorted() }

    func search(_ q: String) -> (todos: [Todo], projects: [Project]) {
        let n = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !n.isEmpty else { return ([], []) }
        let t = s.todos.filter {
            !$0.isHeading && ($0.title.lowercased().contains(n)
                              || $0.notes.lowercased().contains(n)
                              || $0.tags.contains { $0.lowercased().contains(n) })
        }
        return (Array(t.prefix(40)), s.projects.filter { $0.title.lowercased().contains(n) })
    }

    // MARK: - Ändringar

    @discardableResult
    func insert(_ t: Todo, at index: Int?) -> Todo {
        let i = min(max(0, index ?? s.todos.count), s.todos.count)
        s.todos.insert(t, at: i)
        save()
        return t
    }
    func update(_ t: Todo) {
        guard let i = index(of: t.id) else { return }
        s.todos[i] = t
        save()
    }
    func delete(_ id: String) {
        s.todos.removeAll { $0.id == id }
        if s.timer.todoID == id { s.timer.todoID = nil }
        save()
    }
    func setDone(_ id: String, _ done: Bool) {
        guard let i = index(of: id) else { return }
        s.todos[i].done = done
        s.todos[i].completedAt = done ? Date() : nil
        if done, s.timer.todoID == id { s.timer.todoID = nil }
        // En upprepande uppgift föds på nytt i stället för att försvinna.
        // Nästa datum räknas från den dag den VAR planerad, inte från idag —
        // annars glider ett veckoåtagande en dag för varje gång man är sen.
        if done, let rule = s.todos[i].repeatRule {
            var nextOne = s.todos[i]
            nextOne.id = UUID().uuidString
            nextOne.done = false
            nextOne.completedAt = nil
            nextOne.createdAt = Date()
            nextOne.focusedSeconds = 0
            nextOne.sessionCount = 0
            nextOne.checklist = nextOne.checklist.map { var c = $0; c.done = false; return c }
            let base = s.todos[i].when?.day ?? DayKey.today
            nextOne.when = .on(rule.next(after: base))
            if let dl = s.todos[i].deadline {
                let shift = Calendar.current.dateComponents([.day], from: base.date, to: dl.date).day ?? 0
                nextOne.deadline = DayKey(Calendar.current.date(byAdding: .day, value: shift,
                                                                to: nextOne.when!.day!.date) ?? dl.date)
            }
            s.todos.insert(nextOne, at: i)
        }
        save()
    }

    /// Flytta en uppgift i arrayen — ordningen i den ÄR sorteringen.
    func move(_ id: String, before other: String?) {
        guard let from = index(of: id) else { return }
        let item = s.todos.remove(at: from)
        if let other, let to = index(of: other) {
            s.todos.insert(item, at: to)
        } else {
            s.todos.append(item)
        }
        save()
    }

    func focusedSeconds(inProject id: String) -> Int {
        s.todos.filter { $0.projectID == id }.reduce(0) { $0 + $1.focusedSeconds }
    }
    func focusedSeconds(inArea id: AreaID) -> Int {
        s.todos.filter { area(for: $0)?.id == id }.reduce(0) { $0 + $1.focusedSeconds }
    }
    /// Kön. Fokus utför Idag-listan, så nästa uppgift är alltid känd —
    /// det är den som gör de två halvorna till en loop i stället för två öar.
    func nextInToday(after id: String?) -> Todo? {
        let open = items(in: .today).filter { !$0.done }
        guard let id, let i = open.firstIndex(where: { $0.id == id }) else { return open.first }
        return open.indices.contains(i + 1) ? open[i + 1] : open.first { $0.id != id }
    }
    var todayRemaining: Int { items(in: .today).filter { !$0.done }.count }

    /// Dagens plan: hur mycket tid uppgifterna i Idag är tänkta att ta,
    /// och hur mycket som redan är gjort.
    func todayPlan() -> (planned: Int, done: Int) {
        let items = items(in: .today)
        let planned = items.reduce(0) { $0 + $1.durationMinutes * 60 }
        let done = seconds(on: DayKey.today)
        return (planned, done)
    }

    func addProject(_ title: String, in area: AreaID?) -> Project {
        let p = Project(areaID: area, title: title)
        s.projects.append(p)
        save()
        return p
    }
    func deleteProject(_ id: String) {
        s.todos.removeAll { $0.projectID == id }
        s.projects.removeAll { $0.id == id }
        save()
    }
    func update(_ p: Project) {
        guard let i = s.projects.firstIndex(where: { $0.id == p.id }) else { return }
        s.projects[i] = p
        save()
    }

    // MARK: - Timern

    var currentTodo: Todo? { todo(s.timer.todoID) }
    var sessionTitle: String {
        currentTodo?.title.isEmpty == false
            ? currentTodo!.title
            : (Area.of(s.timer.areaID)?.name ?? "Fokus")
    }

    func startTimer() {
        guard s.timer.status != .running else { return }
        guard s.timer.durationSeconds >= 60 else { return }
        if s.timer.status == .idle { s.timer.elapsedBefore = 0 }
        s.timer.status = .running
        s.timer.startedAt = Date()
        startTicking()
        Sound.shared.start(); Haptics.tap()
        scheduleAlarm()
        save()
    }
    func pauseTimer() {
        guard s.timer.status == .running, let st = s.timer.startedAt else { return }
        s.timer.elapsedBefore += Date().timeIntervalSince(st)
        s.timer.status = .paused
        s.timer.startedAt = nil
        stopTicking(); cancelAlarm(); Haptics.tap(); save()
    }
    func resetTimer() {
        s.timer.status = .idle
        s.timer.elapsedBefore = 0
        s.timer.startedAt = nil
        stopTicking(); cancelAlarm(); Haptics.tap(); save()
    }
    /// Avsluta i förtid men behåll tiden. Under en minut är inte ett pass.
    func finishEarly() {
        let secs = Int(s.timer.elapsed)
        guard secs >= 60 else { resetTimer(); return }
        log(seconds: secs, at: Date())
        resetTimer()
        Haptics.success()
    }
    /// Sätts när ett pass tar slut med en uppgift kopplad — vyn frågar då
    /// om uppgiften ska bockas av. Timern gör det inte själv: ett pass är
    /// inte samma sak som att vara klar.
    @Published var finishedTodoID: String?

    func completeTimer(at date: Date = Date()) {
        let todoID = s.timer.todoID
        log(seconds: s.timer.durationSeconds, at: date)
        if let id = todoID, let t = todo(id), !t.done { finishedTodoID = id }
        s.timer.status = .idle
        s.timer.elapsedBefore = 0
        s.timer.startedAt = nil
        stopTicking(); cancelAlarm()
        Sound.shared.done(); Haptics.success()
        save()
    }
    private func log(seconds: Int, at date: Date) {
        s.sessions.insert(Session(areaID: s.timer.areaID, todoID: s.timer.todoID,
                                  title: sessionTitle, seconds: seconds, endedAt: date), at: 0)
        if s.sessions.count > 600 { s.sessions.removeLast(s.sessions.count - 600) }
        if let id = s.timer.todoID, let i = index(of: id) {
            s.todos[i].focusedSeconds += seconds
            s.todos[i].sessionCount += 1
        }
        saveNow()
    }

    /// Ett pass som har tid på sig äger tiden, uppgiften och livsområdet.
    var timeLocked: Bool { s.timer.isLive }

    private func startTicking() {
        ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
            .sink { [weak self] d in
                guard let self else { return }
                self.now = d
                if self.s.timer.status == .running, self.s.timer.remaining <= 0 {
                    let ended = (self.s.timer.startedAt ?? d)
                        .addingTimeInterval(TimeInterval(self.s.timer.durationSeconds) - self.s.timer.elapsedBefore)
                    self.completeTimer(at: min(ended, d))
                }
            }
    }
    private func stopTicking() { ticker?.cancel(); ticker = nil; now = Date() }

    /// Appen kan ha varit helt stängd. Räkna om mot klockan, inte mot minnet.
    func resumeIfNeeded() {
        guard s.timer.status == .running else { return }
        if s.timer.remaining <= 0 {
            let ended = (s.timer.startedAt ?? Date())
                .addingTimeInterval(TimeInterval(s.timer.durationSeconds) - s.timer.elapsedBefore)
            completeTimer(at: min(ended, Date()))
        } else {
            startTicking()
            scheduleAlarm()
        }
    }

    // MARK: - Larmet

    /// Native löser det webbappen aldrig kunde: ett lokalt larm väcker en
    /// släckt telefon utan push-server och utan att appen behöver leva.
    func scheduleAlarm() {
        cancelAlarm()
        guard s.settings.notify, s.timer.status == .running else { return }
        let left = s.timer.remaining
        guard left > 0.5 else { return }
        let c = UNMutableNotificationContent()
        c.title = "Passet är klart 🎉"
        c.body = "\(sessionTitle) — \(Sv.duration(seconds: s.timer.durationSeconds)) avklarat"
        c.sound = .default
        c.interruptionLevel = .timeSensitive
        let req = UNNotificationRequest(
            identifier: "fokus-timer",
            content: c,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: left, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }
    func cancelAlarm() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["fokus-timer"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["fokus-timer"])
    }

    // MARK: - Statistik

    func seconds(on day: DayKey) -> Int {
        s.sessions.filter { DayKey($0.endedAt) == day }.reduce(0) { $0 + $1.seconds }
    }
    func lastSevenDays() -> [(key: DayKey, perArea: [AreaID: Int])] {
        (0..<7).reversed().map { off in
            let k = DayKey.today(offsetBy: -off)
            var m: [AreaID: Int] = [:]
            for s in s.sessions where DayKey(s.endedAt) == k { m[s.areaID, default: 0] += s.seconds }
            return (k, m)
        }
    }
    var streak: Int {
        let days = Set(s.sessions.filter { $0.seconds >= 60 }.map { DayKey($0.endedAt) })
        var n = 0, off = days.contains(DayKey.today) ? 0 : -1
        if off == -1 && !days.contains(DayKey.today(offsetBy: -1)) { return 0 }
        if off == -1 { off = -1 } else { off = 0 }
        while days.contains(DayKey.today(offsetBy: off)) { n += 1; off -= 1 }
        return n
    }
}

// MARK: - Kodning

extension JSONEncoder {
    static var fokus: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }
}
extension JSONDecoder {
    static var fokus: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}
