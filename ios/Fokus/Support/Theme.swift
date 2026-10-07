import SwiftUI

/// Things är till ~95 % neutralt. Färg betyder något — den dekorerar inte.
/// Gult = idag, rött = deadline, indigo = i kväll, livsområdets färg = tillhörighet.
/// Allt annat är vitt, nästan svart och grått.
enum Palette {
    // livsområden
    static let pink   = Color(red: 1.00, green: 0.36, blue: 0.48)
    static let blue   = Color(red: 0.30, green: 0.55, blue: 1.00)
    static let green  = Color(red: 0.08, green: 0.75, blue: 0.55)
    static let amber  = Color(red: 0.96, green: 0.71, blue: 0.26)

    // betydelser
    static let today    = Color(red: 0.94, green: 0.66, blue: 0.18)   // stjärnan
    static let evening  = Color(red: 0.49, green: 0.51, blue: 0.97)   // månen
    static let deadline = Color(red: 0.95, green: 0.27, blue: 0.35)   // flaggan
    static let upcoming = Color(red: 0.91, green: 0.45, blue: 0.29)
    static let anytime  = Color(red: 0.09, green: 0.71, blue: 0.53)
    static let someday  = Color(red: 0.72, green: 0.57, blue: 0.25)
    static let logbook  = Color(red: 0.36, green: 0.68, blue: 0.42)
    static let inbox    = Color(red: 0.36, green: 0.55, blue: 0.94)

    // ytor
    static let bg      = Color(uiColor: .systemGroupedBackground)
    static let card    = Color(uiColor: .secondarySystemGroupedBackground)
    static let sunk    = Color(uiColor: .tertiarySystemGroupedBackground)
    static let hair    = Color(uiColor: .separator).opacity(0.55)
    static let label   = Color(uiColor: .label)
    static let second  = Color(uiColor: .secondaryLabel)
    static let third   = Color(uiColor: .tertiaryLabel)
}

enum Typo {
    static let title    = Font.system(size: 30, weight: .bold,     design: .default)
    static let row      = Font.system(size: 16.5, weight: .regular)
    static let rowBold  = Font.system(size: 16.5, weight: .medium)
    static let meta     = Font.system(size: 12.5, weight: .medium)
    static let section  = Font.system(size: 12.5, weight: .semibold)
    static let heading  = Font.system(size: 13, weight: .bold)
}

extension View {
    /// Things ark: vitt kort, mjuk radie, hårfin skugga.
    func sheetCard() -> some View {
        self.background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

/// En hårfin linje som börjar där texten börjar, som i Things listor.
struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Palette.hair)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}
