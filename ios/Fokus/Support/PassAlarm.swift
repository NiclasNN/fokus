import SwiftUI
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Larmet när ett pass tar slut och appen INTE är framme.
///
/// Med appen öppen spelar appen själv slutklockan (Sound.finish). Det här
/// är bara för låst skärm och bakgrund — därför läggs larmet när appen går
/// i bakgrunden och tas bort när den kommer fram igen. Annars hade båda
/// ringt samtidigt med appen öppen.
///
/// Två vägar:
///  1. AlarmKit (iOS 26) — samma larm som Klocka-appens timer. Hörs även på
///     ljudlöst och genom Fokus-lägen, och ringer tills man trycker Stopp.
///  2. En notis med samma ljud — reserv om AlarmKit saknas eller nekats.
///     Den tystas av ljudlöst-läget; det är iOS regel för notiser.
@MainActor
enum PassAlarm {
    static let soundFile = "fokus-klar.caf"

    // MARK: - Behörighet

    /// Frågas första gången ett pass startas — inte gömt under Mer.
    static func prepare() async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized: return
            case .notDetermined:
                if (try? await AlarmManager.shared.requestAuthorization()) == .authorized { return }
            case .denied: break
            @unknown default: break
            }
        }
        #endif
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
        }
    }

    static var usesAlarmKit: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmManager.shared.authorizationState == .authorized }
        #endif
        return false
    }

    /// Klartext för Mer — vad som faktiskt händer när passet tar slut.
    static func status() async -> (ok: Bool, text: String) {
        if usesAlarmKit {
            return (true, "Larmet ringer som Klocka-appens timer — även på ljudlöst — tills du trycker Stopp.")
        }
        let s = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch s {
        case .authorized, .provisional, .ephemeral:
            return (true, "Larmet kommer som en notis med ljud. Står telefonen på ljudlöst hörs det inte — slå på Larm för Fokus i Inställningar så ringer det ändå.")
        case .denied:
            return (false, "Larm och notiser är avstängda för Fokus. Slå på dem i Inställningar → Fokus, annars märks det inte när passet tar slut med skärmen släckt.")
        default:
            return (false, "Fokus frågar om larm första gången du startar ett pass.")
        }
    }

    // MARK: - Lägga och ta bort

    static func arm(at end: Date, title: String, body: String, tint: Color) async {
        guard end.timeIntervalSinceNow > -5 else { return }
        // Låses telefonen i passets sista sekund ska det ändå ringa — strax
        // efter hellre än inte alls. Appens egen klocka står still i bakgrunden.
        let at = max(end, Date().addingTimeInterval(1.5))
        await disarm()

        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized {
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title))
            } else {
                alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title),
                                                stopButton: AlarmButton(text: "Stopp", textColor: .white,
                                                                        systemImageName: "stop.fill"))
            }
            let attributes = AlarmAttributes<PassMeta>(presentation: AlarmPresentation(alert: alert),
                                                       metadata: PassMeta(), tintColor: tint)
            let config = AlarmManager.AlarmConfiguration<PassMeta>.alarm(
                schedule: .fixed(at), attributes: attributes, sound: .named(soundFile))
            if (try? await AlarmManager.shared.schedule(id: UUID(), configuration: config)) != nil { return }
            // gick det inte att lägga larmet: hellre en notis än tystnad
        }
        #endif

        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = UNNotificationSound(named: UNNotificationSoundName(soundFile))
        c.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, at.timeIntervalSinceNow),
                                                        repeats: false)
        let req = UNNotificationRequest(identifier: "fokus-timer", content: c, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(req)
    }

    /// Tar bort ett väntande larm OCH stoppar ett som redan ringer — öppnar
    /// man appen har man märkt att passet tagit slut.
    static func disarm() async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for a in (try? AlarmManager.shared.alarms) ?? [] {
                if a.state == .alerting { try? AlarmManager.shared.stop(id: a.id) }
                else { try? AlarmManager.shared.cancel(id: a.id) }
            }
        }
        #endif
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["fokus-timer"])
        center.removeDeliveredNotifications(withIdentifiers: ["fokus-timer"])
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct PassMeta: AlarmMetadata {}
#endif
