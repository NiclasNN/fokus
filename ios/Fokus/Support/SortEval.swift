#if DEBUG
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Mäter sorteringen mot ett facit. Körs bara i utvecklingsbygget, och bara
/// när appen startas med `-FokusRunSortEval YES`. Resultatet skrivs till
/// Documents/sort-eval.txt så att det kan läsas utanför appen.
enum SortEval {
    static let cases: [(String, AreaID)] = [
        ("ring mamma", .socialt), ("ring banken om lånet", .pengar), ("ring elektrikern", .struktur),
        ("ring vårdcentralen", .halsa), ("sms:a Erik om helgen", .socialt), ("köp present till pappa", .socialt),
        ("köp mjölk och bröd", .struktur), ("köp nya löparskor", .halsa), ("boka tandläkare", .halsa),
        ("boka bord till middagen med Anna", .socialt), ("boka frisör", .halsa), ("boka hantverkare till badrummet", .struktur),
        ("betala elräkningen", .pengar), ("deklarera", .pengar), ("skicka fakturan till kunden", .pengar),
        ("svara på jobbmejlen", .pengar), ("uppdatera CV:t", .pengar), ("förbered mötet med chefen", .pengar),
        ("plugga till tentan", .pengar), ("städa badrummet", .struktur), ("tvätta", .struktur),
        ("dammsuga vardagsrummet", .struktur), ("handla mat för veckan", .struktur), ("laga cykeln", .struktur),
        ("sortera papper", .struktur), ("gymmet ben", .halsa), ("springa fem kilometer", .halsa),
        ("gå en promenad", .halsa), ("laga nyttiga matlådor", .halsa), ("hämta ut medicinen på apoteket", .halsa),
        ("fika med Sara", .socialt), ("planera mammas födelsedag", .socialt), ("skriv till farmor", .socialt),
        ("träffa grabbarna på fredag", .socialt), ("flytta pengar till sparkontot", .pengar),
        ("göra budget för oktober", .pengar), ("hämta paketet på posten", .struktur), ("byta däck på bilen", .struktur),
        ("sova tidigt", .halsa), ("meditera tio minuter", .halsa),
    ]
    static let rambles = [
        "jag måste ringa banken om lånet och sen ringa mamma ikväll, boka tandläkaren, städa badrummet och gymmet imorgon en timme, köpa present till Sara och svara på jobbmejlen",
        "eh typ handla mat och bröd, fika med Erik på lördag och betala hyran, sen ska jag springa en halvtimme",
    ]

    static func runIfRequested() {
        guard UserDefaults.standard.bool(forKey: "FokusRunSortEval") else { return }
        Task.detached { await run() }
    }

    static func run() async {
        var lines: [String] = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            lines.append("MODELL tillgänglighet: \(SystemLanguageModel.default.availability)")
            do {
                let t = try await OnDevice.parse("ring banken om lånet", examples: []) { _, _ in }
                lines.append("MODELL direktanrop OK: \(t.map { "\($0.title)=\($0.area.rawValue)" })")
            } catch {
                lines.append("MODELL direktanrop FEL: \(error)")
            }
        }
        #endif
        var right = 0, engines: [String: Int] = [:]
        let started = Date()
        for (text, truth) in cases {
            let (tasks, engine) = await BrainDump.parse(text, examples: [])
            engines[engine == .onDevice ? "apple-intelligence" : "enkel", default: 0] += 1
            let got = tasks.first?.area
            if got == truth { right += 1 }
            else { lines.append("MISS  \(text) → \(got?.rawValue ?? "inget") (rätt: \(truth.rawValue)) [\(tasks.count) delar]") }
        }
        lines.insert("AREA \(right)/\(cases.count) motor=\(engines) tid=\(Int(Date().timeIntervalSince(started)))s", at: 0)
        for r in rambles {
            let (tasks, engine) = await BrainDump.parse(r, examples: [])
            lines.append("")
            lines.append("FLÖDE [\(engine == .onDevice ? "apple-intelligence" : "enkel")] \(r)")
            for t in tasks { lines.append("  \(t.title) | \(t.area.rawValue) | \(t.minutes) min | \(t.day.label)") }
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sort-eval.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
