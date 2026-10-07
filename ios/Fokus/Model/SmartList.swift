import SwiftUI

/// De sex listorna äger ingenting. De är vyer över `when` och `deadline`,
/// så en uppgift kan aldrig hamna i två listor som säger emot varandra.
enum SmartList: String, CaseIterable, Identifiable, Hashable {
    case inbox, today, upcoming, anytime, someday, logbook
    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox:    return "Inkorg"
        case .today:    return "Idag"
        case .upcoming: return "Kommande"
        case .anytime:  return "När som helst"
        case .someday:  return "Någon gång"
        case .logbook:  return "Loggbok"
        }
    }
    var symbol: String {
        switch self {
        case .inbox:    return "tray"
        case .today:    return "star.fill"
        case .upcoming: return "calendar"
        case .anytime:  return "square.stack.3d.up.fill"
        case .someday:  return "archivebox.fill"
        case .logbook:  return "book.closed.fill"
        }
    }
    var tint: Color {
        switch self {
        case .inbox:    return Palette.inbox
        case .today:    return Palette.today
        case .upcoming: return Palette.upcoming
        case .anytime:  return Palette.anytime
        case .someday:  return Palette.someday
        case .logbook:  return Palette.logbook
        }
    }
    var empty: (String, String) {
        switch self {
        case .inbox:    return ("Inkorgen är tom", "Allt du fångar utan att sortera hamnar här.")
        case .today:    return ("Inget inplanerat idag", "Lägg till något, eller flytta hit från Kommande.")
        case .upcoming: return ("Inget på kalendern", "Sätt ett datum på en uppgift så dyker den upp här.")
        case .anytime:  return ("Inget att ta tag i", "Uppgifter utan bestämd dag samlas här.")
        case .someday:  return ("Inga idéer parkerade", "Lägg sådant du kanske vill göra här — det stör ingen annan lista.")
        case .logbook:  return ("Inget avklarat ännu", "Bockade uppgifter hamnar här, dag för dag.")
        }
    }
    /// Loggboken är en historik, inte en kö — den ska inte ha en siffra.
    var countsBadge: Bool { self != .logbook }

    func contains(_ t: Todo) -> Bool {
        guard !t.isHeading else { return false }
        if t.done { return self == .logbook }
        let today = DayKey.today
        let overdue = t.deadline.map { $0 <= today } ?? false

        switch self {
        case .inbox:    return !t.isFiled
        // en deadline som gått ut tränger sig in i Idag, precis som i Things
        case .today:    return (t.when?.day.map { $0 <= today } ?? false) || (overdue && t.when != .someday)
        case .upcoming: return t.when?.day.map { $0 > today } ?? false
        case .anytime:  return t.isFiled && t.when != .someday && !(t.when?.day.map { $0 > today } ?? false)
        case .someday:  return t.when == .someday
        case .logbook:  return false
        }
    }

    func contains(_ p: Project) -> Bool {
        if p.done { return self == .logbook }
        let today = DayKey.today
        switch self {
        case .inbox:    return p.areaID == nil
        case .today:    return p.when?.day.map { $0 <= today } ?? false
        case .upcoming: return p.when?.day.map { $0 > today } ?? false
        case .anytime:  return p.areaID != nil && p.when != .someday && !(p.when?.day.map { $0 > today } ?? false)
        case .someday:  return p.when == .someday
        case .logbook:  return false
        }
    }
}

// MARK: - Svenska datumtexter

enum Sv {
    static let weekdays = ["söndag", "måndag", "tisdag", "onsdag", "torsdag", "fredag", "lördag"]
    static let months   = ["jan", "feb", "mars", "apr", "maj", "juni", "juli", "aug", "sep", "okt", "nov", "dec"]

    static func weekday(_ k: DayKey) -> String {
        let i = Calendar.current.component(.weekday, from: k.date) - 1
        return weekdays[max(0, min(6, i))].capitalized
    }
    static func dayAndMonth(_ k: DayKey) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: k.date)
        return "\(c.day ?? 1) \(months[max(0, min(11, (c.month ?? 1) - 1))])"
    }
    /// Rubriken: "Idag", "I morgon", "Fredag" eller "16 okt".
    static func day(_ k: DayKey) -> String {
        switch k.daysFromToday {
        case 0:  return "Idag"
        case 1:  return "I morgon"
        case -1: return "I går"
        case 2...6: return weekday(k)
        default:
            let y = Calendar.current.component(.year, from: k.date)
            let now = Calendar.current.component(.year, from: Date())
            return dayAndMonth(k) + (y == now ? "" : " \(y)")
        }
    }
    /// Underrubriken fyller i det rubriken inte redan sagt.
    static func daySubtitle(_ k: DayKey) -> String {
        let main = day(k), date = dayAndMonth(k), wd = weekday(k)
        if main == date { return wd }
        if main == wd   { return date }
        return "\(wd) · \(date)"
    }
    static func deadline(_ k: DayKey) -> String {
        let n = k.daysFromToday
        if n < 0  { return "\(-n) \(-n == 1 ? "dag" : "dagar") sen" }
        if n == 0 { return "Idag" }
        if n == 1 { return "I morgon" }
        if n <= 14 { return "om \(n) dagar" }
        return day(k)
    }
    static func duration(seconds: Int) -> String {
        let m = Int((Double(seconds) / 60).rounded())
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }
    static func short(seconds: Int) -> String {
        let m = Int((Double(seconds) / 60).rounded())
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
    static func clock(_ t: TimeInterval) -> String {
        // ceil: en nedräkning ska visa 25:00 tills den faktiskt passerat 25:00
        let s = max(0, Int(ceil(t - 1e-6)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%02d:%02d", m, sec)
    }
}
