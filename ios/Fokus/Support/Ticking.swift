import SwiftUI

/// Ritar om sitt innehåll fyra gånger i sekunden medan passet går — bara
/// det, inte resten av appen. Nedräkningen läser klockan direkt
/// (`remaining`), så det räcker att den här lilla delen ritas om.
struct Ticking<Content: View>: View {
    var running: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Samma vy i båda lägena — byttes den ut skulle ratten tappa sin
        // fjäder när passet startar. Utan pass vaknar den en gång i timmen.
        TimelineView(.periodic(from: .now, by: running ? 0.25 : 3600)) { _ in content() }
    }
}
