import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Passet som det ser ut på låsskärmen och i Dynamic Island.
///
/// Delas av appen och widget-tillägget, så de två aldrig kan få olika bild av
/// vad som pågår. Det som står still under ett pass ligger som attribut; bara
/// tiden är tillstånd.
struct FokusAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// När passet tar slut. Systemet räknar ner mot den här själv —
        /// därför tickar låsskärmen vidare utan att appen får leva.
        var endsAt: Date
        var paused: Bool
        /// Bara meningsfull när passet är pausat; då står klockan still.
        var remaining: TimeInterval
    }

    /// Vad du fokuserar på.
    var title: String
    var areaName: String
    var tintHex: String
    var totalSeconds: Int
}

// MARK: - Småsaker som båda sidor behöver

extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt64(s, radix: 16) ?? 0x4C8DFF
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >>  8) & 0xFF) / 255,
                  blue:  Double( v        & 0xFF) / 255,
                  opacity: 1)
    }
    /// Hex utan alfa — Live Activity får bara skicka enkla värden.
    var hexString: String {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "4C8DFF"
        #endif
    }
}

enum FokusClock {
    /// ceil, inte round: en nedräkning ska visa 25:00 tills den faktiskt
    /// passerat 25:00, och 00:01 hela sista sekunden.
    static func text(_ t: TimeInterval) -> String {
        let s = max(0, Int(ceil(t - 1e-6)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%02d:%02d", m, sec)
    }
}
