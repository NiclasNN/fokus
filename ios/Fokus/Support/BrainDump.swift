import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// En uppgift som ännu inte sparats — det användaren granskar innan det
/// hamnar i listorna.
struct DraftTask: Identifiable, Hashable {
    enum Day: String, CaseIterable, Identifiable {
        case none, today, evening, tomorrow
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:     return "När som helst"
            case .today:    return "Idag"
            case .evening:  return "I kväll"
            case .tomorrow: return "I morgon"
            }
        }
        var symbol: String {
            switch self {
            case .none:     return "square.stack.3d.up"
            case .today:    return "star.fill"
            case .evening:  return "moon.fill"
            case .tomorrow: return "calendar"
            }
        }
    }

    let id = UUID()
    var title: String
    var area: AreaID
    var minutes: Int
    var day: Day

    func todo() -> Todo {
        var t = Todo()
        t.title = title
        t.areaID = area
        t.durationMinutes = minutes
        switch day {
        case .none:     t.when = nil
        case .today:    t.when = .on(DayKey.today)
        case .evening:  t.when = .on(DayKey.today); t.evening = true
        case .tomorrow: t.when = .on(DayKey.today(offsetBy: 1))
        }
        return t
    }
}

/// Ett exempel på hur användaren själv sorterar — hämtat ur befintliga uppgifter.
struct SortExample: Hashable {
    let title: String
    let area: AreaID
}

/// Från ett ostrukturerat pratflöde till separata uppgifter med livsområde
/// och tidsuppskattning.
///
/// I första hand Apples språkmodell på telefonen (Apple Intelligence, iOS 26):
/// privat, gratis och utan nät. Saknas den används en ordbaserad sortering.
enum BrainDump {
    enum Engine { case onDevice, simple }

    static var onDeviceReady: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Varför språkmodellen inte används — visas i stället för tystnad.
    static var onDeviceNote: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Slå på Apple Intelligence i Inställningar för den smarta sorteringen."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence laddar fortfarande ner sin modell — prova igen om en stund."
            default: return nil
            }
        }
        #endif
        return nil
    }

    static func parse(_ text: String, examples: [SortExample],
                      progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in })
        async -> (tasks: [DraftTask], engine: Engine) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return ([], .simple) }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), onDeviceReady,
           let tasks = try? await OnDevice.parse(clean, examples: examples, progress: progress),
           !tasks.isEmpty {
            return (tasks, .onDevice)
        }
        #endif
        return (Simple.parse(clean, examples: examples), .simple)
    }

    /// Fokus förval, så uppskattningar landar på tider ratten redan känner.
    static func snap(_ m: Int) -> Int {
        let steps = [5, 10, 15, 20, 25, 30, 45, 60, 75, 90, 120, 150, 180, 240]
        let v = max(5, min(240, m))
        return steps.min { abs($0 - v) < abs($1 - v) } ?? 25
    }

    static func capitalized(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Områdenas betydelse — samma text för modellen som för reserven.
    static let areaGuide = """
    - socialt: relationer. Familj, vänner, partner. Ringa, sms:a eller träffa någon för relationens skull, \
    presenter, kalas, födelsedagar, middag eller fika MED någon.
    - struktur: hem och ordning. Städa, tvätta, diska, handla mat och saker till hemmet, ärenden, \
    fixa och laga saker, boka hantverkare, planera veckan, flytta, sortera papper hemma.
    - pengar: ekonomi och karriär. Jobbuppgifter, fakturor, räkningar, skatt, budget, bank och lån, \
    kunder, jobbmöten, jobbmejl, söka jobb, CV, studier och kurser.
    - halsa: utseende och hälsa. Träna, gym, löpning, promenad för motionens skull, läkare, tandläkare, \
    frisör, hudvård, sömn, laga nyttig mat, apotek.
    Det avgörande är SYFTET, inte verbet: "ring banken" är pengar, "ring mamma" är socialt, \
    "boka tandläkare" är halsa, "boka bord med Anna" är socialt, "boka elektriker" är struktur.
    """

    static let generalExamples: [SortExample] = [
        .init(title: "Ring mamma", area: .socialt),
        .init(title: "Ring banken om lånet", area: .pengar),
        .init(title: "Köp present till pappa", area: .socialt),
        .init(title: "Köp ny dammsugare", area: .struktur),
        .init(title: "Boka tandläkartid", area: .halsa),
        .init(title: "Boka bord till middagen med Anna", area: .socialt),
        .init(title: "Boka elektriker", area: .struktur),
        .init(title: "Betala elräkningen", area: .pengar),
        .init(title: "Skicka offerten till kunden", area: .pengar),
        .init(title: "Uppdatera CV:t", area: .pengar),
        .init(title: "Handla mat för veckan", area: .struktur),
        .init(title: "Laga matlådor till veckan", area: .halsa),
        .init(title: "Städa badrummet", area: .struktur),
        .init(title: "Gymmet — ben", area: .halsa),
        .init(title: "Klippa håret", area: .halsa),
        .init(title: "Fika med Erik", area: .socialt),
    ]
}

// MARK: - Apple Intelligence

#if canImport(FoundationModels)
/// Steg 1: dela upp. Inget sorteras här — bara vad som är separata saker.
@available(iOS 26.0, *)
@Generable
struct SplitTask {
    @Guide(description: "Short, concrete task in Swedish, starting with a verb. Keep every name, place and detail the person said. At most about eight words.")
    var title: String

    @Guide(description: "When the person said it should happen.", .anyOf(["idag", "ikvall", "imorgon", "ingen"]))
    var when: String

    @Guide(description: "Minutes, only if the person explicitly said how long it takes (\"en timme\" = 60, \"en halvtimme\" = 30, \"en kvart\" = 15). Otherwise 0.", .range(0...240))
    var saidMinutes: Int
}

@available(iOS 26.0, *)
@Generable
struct SplitPlan {
    @Guide(description: "One entry per distinct thing to do, in the order they were said.")
    var tasks: [SplitTask]
}

/// Steg 2: sortera EN uppgift. Fältordningen är genereringsordningen —
/// modellen beskriver syftet innan den väljer område, och väljer bättre så.
@available(iOS 26.0, *)
@Generable
struct SortedTask {
    @Guide(description: "One short Swedish sentence: what is the purpose of this task, and who or what does it concern?")
    var purpose: String

    @Guide(description: "The life area the purpose belongs to.", .anyOf(["socialt", "struktur", "pengar", "halsa"]))
    var area: String

    @Guide(description: "Realistic focused minutes to actually do it: a quick call 10-15, a workout 45-60, cleaning a room 30, paying a bill 10, a work meeting 60.", .range(5...240))
    var minutes: Int
}

@available(iOS 26.0, *)
enum OnDevice {
    static let splitInstructions = """
    Du delar upp en pratad, rörig svensk att-göra-lista i separata uppgifter.
    En uppgift per sak personen behöver göra. Hoppa över utfyllnadsord, tvekan och upprepningar.
    Hitta aldrig på uppgifter som inte sades. Slå aldrig ihop två olika saker till en.
    Behåll namn och detaljer exakt som de sades.
    """

    static func sortInstructions(_ examples: [SortExample]) -> String {
        let lines = examples.map { "\"\($0.title)\" → \($0.area.rawValue)" }.joined(separator: "\n")
        return """
        Du sorterar en uppgift i rätt livsområde och uppskattar hur lång tid den tar.

        Livsområden:
        \(BrainDump.areaGuide)

        Så här sorterar den här personen själv — följ samma mönster:
        \(lines)
        """
    }

    static func parse(_ text: String, examples: [SortExample],
                      progress: @escaping @MainActor (Int, Int) -> Void) async throws -> [DraftTask] {
        let splitter = LanguageModelSession(instructions: splitInstructions)
        let plan = try await splitter.respond(to: text, generating: SplitPlan.self).content
        let pieces = plan.tasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }

        // Personens egna uppgifter först — de definierar vad områdena betyder för just hen.
        var seen = Set<String>()
        let pool = (examples + BrainDump.generalExamples).filter {
            seen.insert($0.title.lowercased()).inserted
        }
        let instructions = sortInstructions(Array(pool.prefix(36)))

        var out: [DraftTask] = []
        for (i, piece) in pieces.enumerated() {
            await progress(i + 1, pieces.count)
            let lower = piece.title.lowercased()
            // Det den mätta sorteringen är säker på avgör den själv. Modellen
            // får bara de verkligt tvetydiga fallen — där nyckelord inte räcker.
            let sure = Simple.confidentArea(for: lower, examples: examples, original: text)
            var sorted: SortedTask?
            if sure == nil {
                // ny session per uppgift, så föregående svar inte färgar nästa
                let sorter = LanguageModelSession(instructions: instructions)
                sorted = try? await sorter.respond(to: "Uppgift: \(piece.title)", generating: SortedTask.self).content
            }
            let area = sure
                ?? sorted.flatMap { AreaID(rawValue: $0.area) }
                ?? Simple.area(for: lower, examples: examples, original: text)
            let minutes = piece.saidMinutes > 0 ? piece.saidMinutes
                : (sorted?.minutes ?? Simple.minutes(in: piece.title.lowercased(), area: area))
            let day: DraftTask.Day = switch piece.when {
                case "idag": .today
                case "ikvall": .evening
                case "imorgon": .tomorrow
                default: .none
            }
            out.append(DraftTask(title: BrainDump.capitalized(piece.title), area: area,
                                 minutes: BrainDump.snap(minutes), day: day))
        }
        return out
    }
}
#endif

// MARK: - Ordbaserad sortering

/// Reserven när Apple Intelligence saknas. Delar på skiljetecken och tydliga
/// övergångsord. Området tas i första hand från den mest lika av användarens
/// egna uppgifter, i andra hand från nyckelord.
enum Simple {
    static func parse(_ text: String, examples: [SortExample]) -> [DraftTask] {
        var t = " " + text.lowercased() + " "
        for sep in [" och sen ", " och så ", " och sedan ", " sen ", " sedan ", " också ",
                    " dessutom ", " plus ", " samt ", " efter det "] {
            t = t.replacingOccurrences(of: sep, with: ". ")
        }
        let parts = t.components(separatedBy: CharacterSet(charactersIn: ".,;!?\n"))
            .flatMap(splitOnAnd)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 2 }

        // namn behöver versalerna från originaltexten
        let original = text
        return parts.compactMap { raw in
            var title = strip(raw)
            guard title.count > 2 else { return nil }
            // Uppdelningen sker i gemener; hämta tillbaka originalets versaler
            // så att "sara" blir "Sara" igen.
            if let r = original.range(of: title, options: .caseInsensitive) { title = String(original[r]) }
            let area = area(for: raw, examples: examples, original: original)
            return DraftTask(title: BrainDump.capitalized(title), area: area,
                             minutes: BrainDump.snap(minutes(in: raw, area: area)), day: day(in: raw))
        }
    }

    /// Verb som inleder en ny sak. "...och städa" är en ny uppgift,
    /// "...och bröd" är det inte.
    static let starters = ["ringa", "ring", "städa", "betala", "handla", "köpa", "köp", "tvätta",
                           "boka", "träna", "gå", "laga", "fixa", "skicka", "svara", "plugga",
                           "hämta", "lämna", "springa", "dammsuga", "diska", "maila", "mejla",
                           "skriva", "träffa", "fika", "planera", "deklarera", "sms", "ta"]

    /// Delar på " och " bara när det verkligen är två saker: antingen börjar
    /// andra halvan med ett handlingsverb, eller så hör halvorna till olika
    /// livsområden. "Köp mjölk och bröd" och "ring mamma och pappa" hålls ihop.
    static func splitOnAnd(_ s: String) -> [String] {
        let pieces = s.components(separatedBy: " och ")
        guard pieces.count > 1 else { return [s] }
        var out = [pieces[0]]
        for next in pieces.dropFirst() {
            let prev = out[out.count - 1]
            let first = next.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
            let a = keywordArea(prev), b = keywordArea(next)
            if starters.contains(first) || (a != nil && b != nil && a != b) {
                out.append(next)
            } else {
                out[out.count - 1] = prev + " och " + next
            }
        }
        return out
    }

    /// "jag måste ringa mamma ikväll" → "ringa mamma"
    static func strip(_ s: String) -> String {
        var t = s
        let fillers = ["jag måste ", "jag ska ", "jag behöver ", "jag borde ", "jag vill ",
                       "glöm inte att ", "kom ihåg att ", "måste ", "ska ", "behöver ",
                       "borde ", "och ", "eh ", "öh ", "typ ", "alltså ", "att ", "jag "]
        var changed = true
        while changed {
            changed = false
            for f in fillers where t.hasPrefix(f) { t.removeFirst(f.count); changed = true }
        }
        for d in [" idag", " i dag", " ikväll", " i kväll", " imorgon", " i morgon"] {
            t = t.replacingOccurrences(of: d, with: "")
        }
        t = t.replacingOccurrences(of: #"\s*(i\s+)?(\d+|en|ett|två|tre)\s+(minuter|min|timmar|timme|h)\b"#,
                                   with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s*(en\s+)?(halvtimme|kvart)\b"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func day(in s: String) -> DraftTask.Day {
        if s.contains("ikväll") || s.contains("i kväll") { return .evening }
        if s.contains("imorgon") || s.contains("i morgon") { return .tomorrow }
        if s.contains("idag") || s.contains("i dag") { return .today }
        return .none
    }

    static let keywords: [(AreaID, [String])] = [
        (.socialt, ["mamma", "pappa", "mormor", "morfar", "farmor", "farfar", "syster", "bror",
                    "kompis", "vän", "grabbar", "tjejer", "flickvän", "pojkvän", "sambo", "fru", "middag", "fika",
                    "träffa", "födelsedag", "present", "kalas", "sms", "skriv till", "dejt", "bjud", "hälsa på"]),
        (.pengar,  ["faktur", "betala", "räkning", "skatt", "deklar", "lön", "budget", "spara", "bank",
                    "lån", "pengar", "konto", "swish", "aktie", "fond", "investera", "försäkring",
                    "jobb", "arbete", "möte", "kund", "mejl", "mail", "cv", "ansök", "intervju",
                    "offert", "bokför", "chef", "rapport", "presentation", "sälj", "plugga", "tenta", "kurs"]),
        (.halsa,   ["gym", "träna", "träning", "löp", "spring", "yoga", "promenad", "tandläkare", "läkare",
                    "doktor", "vårdcentral", "frisör", "klipp", "hud", "sova", "sömn", "vitamin", "meditera",
                    "apotek", "naglar", "stretch", "simma", "matlåd", "nyttig"]),
        (.struktur,["städa", "tvätt", "disk", "handla", "köp", "fixa", "laga", "organisera", "rensa",
                    "planera", "flytt", "sortera", "packa", "dammsug", "sopor", "post", "hämta",
                    "lämna", "byta", "montera", "skura", "elektriker", "rörmokare"]),
    ]

    /// Verb och småord som inte säger något om ämnet. "Ring mamma" och
    /// "ring banken" delar ordet "ring" men inte livsområde.
    static let neutral: Set<String> = ["ring", "ringa", "köp", "köpa", "boka", "fixa", "göra", "gör",
        "skicka", "skriv", "skriva", "svara", "hämta", "lämna", "kolla", "titta", "läsa", "planera",
        "förbered", "förbereda", "till", "från", "efter", "innan", "inför", "helgen", "veckan", "imorgon",
        "idag", "ikväll", "måste", "behöver", "ska", "nästa", "några", "lite", "massa", "mycket"]

    static func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter }.map(String.init)
            .filter { $0.count >= 4 && !neutral.contains($0) })
    }

    /// Bara nyckelorden — nil om inget ord känns igen.
    static func keywordArea(_ s: String) -> AreaID? {
        var top: (AreaID?, Int) = (nil, 0)
        for (a, list) in keywords {
            let hits = list.filter { s.contains($0) }.count
            if hits > top.1 { top = (a, hits) }
        }
        return top.0
    }

    /// Området, men BARA när det är otvetydigt: en träff i användarens egna
    /// uppgifter, ett namn efter en preposition, eller nyckelord från exakt
    /// ett område. Annars nil — då är det ett fall för språkmodellen.
    static func confidentArea(for s: String, examples: [SortExample], original: String = "") -> AreaID? {
        let w = words(s)
        if let best = examples.map({ ($0.area, words($0.title).intersection(w).count) }).max(by: { $0.1 < $1.1 }),
           best.1 > 0 { return best.0 }
        if hasNamedPerson(s, original: original) { return .socialt }
        let hit = keywords.filter { _, list in list.contains { s.contains($0) } }.map(\.0)
        return hit.count == 1 ? hit[0] : nil
    }

    static func hasNamedPerson(_ s: String, original: String) -> Bool {
        guard !original.isEmpty, let r = original.range(of: s, options: .caseInsensitive) else { return false }
        return String(original[r]).range(of: #"\b(med|till|åt|hos)\s+[A-ZÅÄÖ][a-zåäö]+"#,
                                         options: .regularExpression) != nil
    }

    static func area(for s: String, examples: [SortExample], original: String = "") -> AreaID {
        // Användarens egna uppgifter väger tyngst: delar man ett ämnesord med
        // en uppgift hen redan sorterat, är det hens sortering som gäller.
        let w = words(s)
        let best = examples
            .map { ($0.area, words($0.title).intersection(w).count) }
            .max { $0.1 < $1.1 }
        if let best, best.1 > 0 { return best.0 }

        // "med Anna", "till Erik" — ett namn efter en preposition är en person.
        if !original.isEmpty, let r = original.range(of: s, options: .caseInsensitive) {
            let piece = String(original[r])
            if piece.range(of: #"\b(med|till|åt|hos)\s+[A-ZÅÄÖ][a-zåäö]+"#, options: .regularExpression) != nil {
                return .socialt
            }
        }
        return keywordArea(s) ?? .struktur
    }

    static func minutes(in s: String, area: AreaID) -> Int {
        let numerals = ["en": 1, "ett": 1, "två": 2, "tre": 3, "fyra": 4]
        if s.contains("halvtimme") { return 30 }
        if s.contains("kvart") { return 15 }
        if let m = s.range(of: #"(\d+|en|ett|två|tre|fyra)\s+(timmar|timme|h)\b"#, options: .regularExpression) {
            let n = s[m].split(separator: " ").first.map(String.init) ?? "1"
            return (Int(n) ?? numerals[n] ?? 1) * 60
        }
        if let m = s.range(of: #"(\d+)\s*(minuter|min)\b"#, options: .regularExpression) {
            return Int(s[m].prefix { $0.isNumber }) ?? 25
        }
        let guesses: [(String, Int)] = [("ring", 15), ("sms", 5), ("mejl", 15), ("mail", 15),
                                        ("betala", 10), ("gym", 60), ("träna", 60), ("löp", 45),
                                        ("spring", 45), ("promenad", 30), ("städa", 30), ("dammsug", 20),
                                        ("tvätt", 45), ("disk", 15), ("handla", 30), ("middag", 90),
                                        ("möte", 60), ("tandläkare", 60), ("läkare", 60), ("frisör", 60),
                                        ("plugga", 60), ("faktur", 25), ("deklar", 60), ("fika", 60)]
        return guesses.first { s.contains($0.0) }?.1 ?? 25
    }
}
