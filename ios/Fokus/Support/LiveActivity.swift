import SwiftUI
import ActivityKit

/// Passet på låsskärmen.
///
/// Appen startar aktiviteten och skickar sedan nästan ingenting: slutdatumet
/// räcker för att systemet ska räkna ner själv. Uppdateringar behövs bara när
/// något FAKTISKT ändras — paus, återupptagning, slut. Därför tickar
/// låsskärmen vidare med släckt skärm utan att appen kostar ström.
/// Slutdatumet är också `staleDate`: tar passet slut medan appen sover
/// visar låsskärmen "Klart" i stället för att stå på 00:00.
@MainActor
enum FokusLive {
    private static var current: Activity<FokusAttributes>?

    private static var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Efter en omstart lever aktiviteten kvar i systemet — adoptera den i
    /// stället för att starta en till.
    static func adopt() {
        if current == nil { current = Activity<FokusAttributes>.activities.first }
    }

    static func start(title: String, areaName: String, tint: Color,
                      totalSeconds: Int, endsAt: Date) {
        adopt()
        guard enabled else { return }
        let state = FokusAttributes.ContentState(endsAt: endsAt, paused: false,
                                                 remaining: endsAt.timeIntervalSinceNow)
        // Samma pass som redan visas? Uppdatera, starta inte om.
        if let a = current, a.attributes.title == title {
            Task { await a.update(ActivityContent(state: state, staleDate: endsAt)) }
            return
        }
        if current != nil { end() }
        let attrs = FokusAttributes(title: title, areaName: areaName,
                                    tintHex: tint.hexString, totalSeconds: totalSeconds)
        do {
            current = try Activity.request(attributes: attrs,
                                           content: ActivityContent(state: state, staleDate: endsAt),
                                           pushType: nil)
        } catch {
            // Användaren kan ha stängt av liveaktiviteter för appen. Passet
            // fungerar ändå — låsskärmen är en extra yta, inte en förutsättning.
        }
    }

    static func pause(remaining: TimeInterval) {
        adopt()
        guard let a = current else { return }
        let state = FokusAttributes.ContentState(endsAt: Date().addingTimeInterval(remaining),
                                                 paused: true, remaining: remaining)
        Task { await a.update(ActivityContent(state: state, staleDate: nil)) }
    }

    static func resume(endsAt: Date) {
        adopt()
        guard let a = current else { return }
        let state = FokusAttributes.ContentState(endsAt: endsAt, paused: false,
                                                 remaining: endsAt.timeIntervalSinceNow)
        Task { await a.update(ActivityContent(state: state, staleDate: endsAt)) }
    }

    static func end() {
        adopt()
        guard let a = current else { return }
        current = nil
        let state = FokusAttributes.ContentState(endsAt: Date(), paused: true, remaining: 0)
        Task { await a.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
    }
}
