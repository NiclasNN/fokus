import Foundation

/// Läser både appens egen backup och en export från webbversionen.
/// Webbens fältnamn skiljer sig (catId/durationMs/focusedMs), så den
/// översätts här i stället för att smutsa ner modellen med alias.
@MainActor
enum Importer {

    static func export(_ store: Store) -> Data {
        (try? JSONEncoder.fokus.encode(store.s)) ?? Data()
    }

    static func load(_ url: URL, into store: Store) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return "Kunde inte öppna filen." }

        // 1. appens eget format
        if let state = try? JSONDecoder.fokus.decode(AppState.self, from: data) {
            store.s = state
            store.saveNow()
            Haptics.success()
            return "Importerat: \(state.todos.filter { !$0.isHeading }.count) uppgifter."
        }
        // 2. webbversionens export
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Filen är inte en Fokus-backup."
        }
        return importWeb(raw, into: store)
    }

    private static func importWeb(_ raw: [String: Any], into store: Store) -> String {
        guard let tasks = raw["tasks"] as? [[String: Any]] else {
            return "Filen saknar uppgifter."
        }
        var state = AppState()

        for p in (raw["projects"] as? [[String: Any]]) ?? [] {
            var proj = Project()
            proj.id = p["id"] as? String ?? UUID().uuidString
            proj.areaID = (p["catId"] as? String).flatMap(AreaID.init(rawValue:))
            proj.title = p["title"] as? String ?? ""
            proj.notes = p["notes"] as? String ?? ""
            proj.when = when(p["when"])
            proj.deadline = (p["deadline"] as? String).flatMap { DayKey(raw: $0) }
            proj.done = p["done"] as? Bool ?? false
            proj.createdAt = date(p["createdAt"]) ?? Date()
            state.projects.append(proj)
        }

        for t in tasks {
            var todo = Todo()
            todo.id = t["id"] as? String ?? UUID().uuidString
            todo.kind = (t["type"] as? String) == "heading" ? .heading : .todo
            todo.areaID = (t["catId"] as? String).flatMap(AreaID.init(rawValue:))
            todo.projectID = t["projectId"] as? String
            todo.title = t["title"] as? String ?? ""
            todo.notes = t["notes"] as? String ?? ""
            todo.tags = t["tags"] as? [String] ?? []
            todo.checklist = ((t["checklist"] as? [[String: Any]]) ?? []).map {
                ChecklistItem(id: $0["id"] as? String ?? UUID().uuidString,
                              title: $0["title"] as? String ?? "",
                              done: $0["done"] as? Bool ?? false)
            }
            todo.when = when(t["when"])
            todo.evening = t["evening"] as? Bool ?? false
            todo.deadline = (t["deadline"] as? String).flatMap { DayKey(raw: $0) }
            todo.durationMinutes = max(1, Int((t["durationMs"] as? Double ?? 1_500_000) / 60_000))
            todo.done = t["done"] as? Bool ?? false
            todo.completedAt = date(t["completedAt"])
            todo.createdAt = date(t["createdAt"]) ?? Date()
            todo.focusedSeconds = Int((t["focusedMs"] as? Double ?? 0) / 1000)
            todo.sessionCount = t["sessions"] as? Int ?? 0
            state.todos.append(todo)
        }

        for s in (raw["sessions"] as? [[String: Any]]) ?? [] {
            guard let area = (s["catId"] as? String).flatMap(AreaID.init(rawValue:)),
                  let ended = date(s["endedAt"]) else { continue }
            state.sessions.append(Session(
                id: s["id"] as? String ?? UUID().uuidString,
                areaID: area,
                todoID: s["taskId"] as? String,
                title: s["title"] as? String ?? "",
                seconds: Int((s["ms"] as? Double ?? 0) / 1000),
                endedAt: ended))
        }

        if let set = raw["settings"] as? [String: Any] {
            state.settings.sound = set["sound"] as? Bool ?? true
            state.settings.haptics = set["haptics"] as? Bool ?? true
            state.settings.notify = set["notify"] as? Bool ?? true
            state.settings.lastDurationMinutes = set["lastDurMin"] as? Int ?? 25
            if let th = set["theme"] as? String, let t = Settings.Theme(rawValue: th) {
                state.settings.theme = t
            }
        }
        // Timern tas medvetet INTE med: ett pass som räknade på en annan
        // enhet ska inte plötsligt vara igång här.
        store.s = state
        store.saveNow()
        Haptics.success()
        let n = state.todos.filter { !$0.isHeading }.count
        return "Importerat från webbversionen: \(n) uppgifter, \(state.projects.count) projekt, \(state.sessions.count) pass."
    }

    private static func when(_ v: Any?) -> When? {
        guard let s = v as? String else { return nil }
        if s == "someday" { return .someday }
        return DayKey(raw: s).map { .on($0) }
    }
    private static func date(_ v: Any?) -> Date? {
        guard let ms = v as? Double, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
