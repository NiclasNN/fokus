import UIKit

/// Det här är hela poängen med att gå native: iOS kan faktiskt vibrera.
/// Safari har inget Vibration API, så webbversionen kunde aldrig göra det här.
@MainActor
enum Haptics {
    static var enabled = true

    private static let selection = UISelectionFeedbackGenerator()
    private static let light  = UIImpactFeedbackGenerator(style: .light)
    private static let rigid  = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy  = UIImpactFeedbackGenerator(style: .heavy)
    private static let notice = UINotificationFeedbackGenerator()

    /// Ratten står still mellan minuterna — varna motorn innan draget börjar.
    static func prepareDial() {
        guard enabled else { return }
        selection.prepare(); rigid.prepare(); heavy.prepare()
    }
    static func tick()      { guard enabled else { return }; selection.selectionChanged() }
    static func fiveTick()  { guard enabled else { return }; rigid.impactOccurred(intensity: 0.7) }
    static func hourTick()  { guard enabled else { return }; heavy.impactOccurred() }
    static func tap()       { guard enabled else { return }; light.impactOccurred(intensity: 0.6) }
    static func press()     { guard enabled else { return }; rigid.impactOccurred(intensity: 0.8) }
    static func success()   { guard enabled else { return }; notice.notificationOccurred(.success) }
    static func warning()   { guard enabled else { return }; notice.notificationOccurred(.warning) }
}
