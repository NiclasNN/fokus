import Foundation
import SwiftUI

// MARK: - Dag

/// En dag, inte ett ögonblick. Lagras som "ÅÅÅÅ-MM-DD" — samma format som
/// webbappen, så en export därifrån kan läsas rakt av.
struct DayKey: Hashable, Comparable, Codable, CustomStringConvertible {
    let raw: String

    init?(raw: String) {
        guard raw.count == 10, raw.dropFirst(4).first == "-" else { return nil }
        self.raw = raw
    }
    init(_ date: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        raw = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static var today: DayKey { DayKey(Date()) }
    static func today(offsetBy days: Int) -> DayKey {
        DayKey(Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
    }

    var date: Date {
        let p = raw.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date() }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) ?? Date()
    }
    /// Hela dagar från idag. Negativt = passerat.
    var daysFromToday: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                        to: Calendar.current.startOfDay(for: date)).day ?? 0
    }

    var description: String { raw }
    static func < (a: DayKey, b: DayKey) -> Bool { a.raw < b.raw }

    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let k = DayKey(raw: s) else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                   debugDescription: "ogiltig dag: \(s)")
        }
        self = k
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

// MARK: - När

/// Things två begrepp hålls isär: `when` är när du tänkt göra uppgiften,
/// `deadline` när den måste vara klar. Listorna läser bara de här fälten.
enum When: Hashable, Codable {
    case someday
    case on(DayKey)

    var day: DayKey? { if case .on(let k) = self { return k }; return nil }

    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        if s == "someday" { self = .someday }
        else if let k = DayKey(raw: s) { self = .on(k) }
        else { throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                      debugDescription: "ogiltigt när: \(s)") }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .someday:    try c.encode("someday")
        case .on(let k):  try c.encode(k.raw)
        }
    }
}

// MARK: - Livsområde

enum AreaID: String, Codable, CaseIterable, Identifiable {
    case socialt, struktur, pengar, halsa
    var id: String { rawValue }
}

struct Area: Identifiable, Hashable {
    let id: AreaID
    let name: String
    let short: String
    let symbol: String
    let tint: Color

    static let all: [Area] = [
        Area(id: .socialt,  name: "Socialt",         short: "Socialt",  symbol: "person.2.fill",      tint: Palette.pink),
        Area(id: .struktur, name: "Struktur",        short: "Struktur", symbol: "square.grid.2x2.fill", tint: Palette.blue),
        Area(id: .pengar,   name: "Pengar/Karriär",  short: "Pengar",   symbol: "dollarsign.circle.fill", tint: Palette.green),
        Area(id: .halsa,    name: "Utseende/Hälsa",  short: "Hälsa",    symbol: "heart.fill",         tint: Palette.amber),
    ]
    static func of(_ id: AreaID?) -> Area? { id.flatMap { aid in all.first { $0.id == aid } } }
}

// MARK: - Uppgift

struct ChecklistItem: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var title: String = ""
    var done: Bool = false
}

/// En uppgift som kommer tillbaka. Things kallar det repeating to-do:
/// när du bockar av den föds nästa på nästa datum.
enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case daily, weekdays, weekly, biweekly, monthly, yearly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .daily:    return "Varje dag"
        case .weekdays: return "Varje vardag"
        case .weekly:   return "Varje vecka"
        case .biweekly: return "Varannan vecka"
        case .monthly:  return "Varje månad"
        case .yearly:   return "Varje år"
        }
    }
    /// Nästa dag efter `from`. Vardagsregeln hoppar över helgen.
    func next(after from: DayKey) -> DayKey {
        let cal = Calendar.current
        let d = from.date
        func add(_ comp: Calendar.Component, _ n: Int) -> DayKey {
            DayKey(cal.date(byAdding: comp, value: n, to: d) ?? d)
        }
        switch self {
        case .daily:    return add(.day, 1)
        case .weekdays:
            var k = add(.day, 1)
            while [1, 7].contains(cal.component(.weekday, from: k.date)) {
                k = DayKey(cal.date(byAdding: .day, value: 1, to: k.date) ?? k.date)
            }
            return k
        case .weekly:   return add(.day, 7)
        case .biweekly: return add(.day, 14)
        case .monthly:  return add(.month, 1)
        case .yearly:   return add(.year, 1)
        }
    }
}

struct Todo: Identifiable, Hashable, Codable {
    enum Kind: String, Codable { case todo, heading }

    var id: String = UUID().uuidString
    var kind: Kind = .todo
    var areaID: AreaID?
    var projectID: String?
    var title: String = ""
    var notes: String = ""
    var checklist: [ChecklistItem] = []
    var tags: [String] = []
    var when: When?
    var evening: Bool = false
    var deadline: DayKey?
    var durationMinutes: Int = 25
    var done: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()
    var focusedSeconds: Int = 0
    var sessionCount: Int = 0
    var repeatRule: RepeatRule?

    var isHeading: Bool { kind == .heading }
    /// Sorterad någonstans? Inkorgen är precis det som inte är det.
    var isFiled: Bool { areaID != nil || projectID != nil }
    var openChecklist: Int { checklist.filter { !$0.done }.count }
}

struct Project: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var areaID: AreaID?
    var title: String = ""
    var notes: String = ""
    var when: When?
    var deadline: DayKey?
    var done: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()
}

struct Session: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var areaID: AreaID
    var todoID: String?
    var title: String
    var seconds: Int
    var endedAt: Date
}

// MARK: - Timern

/// Tiden räknas alltid ut från klockan, aldrig genom att räkna ner en variabel.
/// Därför stämmer den även om appen varit helt stängd.
struct TimerState: Codable, Hashable {
    enum Status: String, Codable { case idle, running, paused }

    var status: Status = .idle
    var areaID: AreaID = .struktur
    var todoID: String?
    var durationSeconds: Int = 25 * 60
    var startedAt: Date?
    var elapsedBefore: TimeInterval = 0

    var elapsed: TimeInterval {
        guard status == .running, let s = startedAt else { return elapsedBefore }
        return elapsedBefore + Date().timeIntervalSince(s)
    }
    var remaining: TimeInterval { max(0, TimeInterval(durationSeconds) - elapsed) }
    var isLive: Bool { status != .idle }
}

struct Settings: Codable, Hashable {
    enum Theme: String, Codable, CaseIterable { case system, light, dark }
    var theme: Theme = .system
    var sound: Bool = true
    var haptics: Bool = true
    var notify: Bool = true
    var keepAwake: Bool = false
    var lastDurationMinutes: Int = 25
}

// MARK: - Allt på disk

struct AppState: Codable {
    var version: Int = 2
    var todos: [Todo] = []
    var projects: [Project] = []
    var sessions: [Session] = []
    var timer: TimerState = TimerState()
    var settings: Settings = Settings()
}

// MARK: - Tålig avkodning
//
// Swift fyller INTE i en egenskaps standardvärde när nyckeln saknas i JSON —
// ett enda bortglömt fält får hela inläsningen att kasta, och appen hade då
// startat tom. För något som äger användarens enda kopia av datan är det fel
// beteende. Därför läses varje fält med decodeIfPresent och ett fall tillbaka.

extension Todo {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind            = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .todo
        areaID          = try c.decodeIfPresent(AreaID.self, forKey: .areaID)
        projectID       = try c.decodeIfPresent(String.self, forKey: .projectID)
        title           = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes           = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        checklist       = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
        tags            = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        when            = try c.decodeIfPresent(When.self, forKey: .when)
        evening         = try c.decodeIfPresent(Bool.self, forKey: .evening) ?? false
        deadline        = try c.decodeIfPresent(DayKey.self, forKey: .deadline)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 25
        done            = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        completedAt     = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt       = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        focusedSeconds  = try c.decodeIfPresent(Int.self, forKey: .focusedSeconds) ?? 0
        sessionCount    = try c.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        repeatRule      = try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule)
    }
}

extension ChecklistItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        done  = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
}

extension Project {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        areaID      = try c.decodeIfPresent(AreaID.self, forKey: .areaID)
        title       = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes       = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        when        = try c.decodeIfPresent(When.self, forKey: .when)
        deadline    = try c.decodeIfPresent(DayKey.self, forKey: .deadline)
        done        = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt   = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

extension Session {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        areaID  = try c.decodeIfPresent(AreaID.self, forKey: .areaID) ?? .struktur
        todoID  = try c.decodeIfPresent(String.self, forKey: .todoID)
        title   = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds) ?? 0
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt) ?? Date()
    }
}

extension TimerState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status          = try c.decodeIfPresent(Status.self, forKey: .status) ?? .idle
        areaID          = try c.decodeIfPresent(AreaID.self, forKey: .areaID) ?? .struktur
        todoID          = try c.decodeIfPresent(String.self, forKey: .todoID)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 25 * 60
        startedAt       = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        elapsedBefore   = try c.decodeIfPresent(TimeInterval.self, forKey: .elapsedBefore) ?? 0
    }
}

extension Settings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme     = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? .system
        sound     = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        haptics   = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        notify    = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? true
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? false
        lastDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .lastDurationMinutes) ?? 25
    }
}

extension AppState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version  = try c.decodeIfPresent(Int.self, forKey: .version) ?? 2
        todos    = try c.decodeIfPresent([Todo].self, forKey: .todos) ?? []
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        timer    = try c.decodeIfPresent(TimerState.self, forKey: .timer) ?? TimerState()
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
    }
}
