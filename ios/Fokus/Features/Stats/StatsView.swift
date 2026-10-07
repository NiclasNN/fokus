import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    kpis
                    card("Senaste 7 dagarna", meta: Sv.duration(seconds: weekSeconds)) { week }
                    card("Balans mellan områden", meta: "senaste 7 dagarna") { balance }
                    card("Senaste passen", meta: nil) { sessions }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 24)
            }
            .background(Palette.bg)
            .navigationTitle("Statistik")
        }
    }

    private var days: [(key: DayKey, perArea: [AreaID: Int])] { store.lastSevenDays() }
    private var weekSeconds: Int { days.reduce(0) { $0 + $1.perArea.values.reduce(0, +) } }

    private var kpis: some View {
        HStack(spacing: 9) {
            kpi("Idag", Sv.duration(seconds: store.seconds(on: DayKey.today)))
            kpi("7 dagar", Sv.duration(seconds: weekSeconds))
            kpi("Dagar i rad", "\(store.streak)")
        }
    }
    private func kpi(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 21, weight: .light)).monospacedDigit()
                .foregroundStyle(Palette.label).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.third)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .sheetCard()
    }

    private func card<C: View>(_ title: String, meta: String?,
                               @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 15.5, weight: .semibold))
                Spacer()
                if let m = meta { Text(m).font(Typo.meta).foregroundStyle(Palette.third) }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheetCard()
    }

    private var week: some View {
        let maxV = max(1, days.map { $0.perArea.values.reduce(0, +) }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 7) {
            ForEach(days, id: \.key) { d in
                let total = d.perArea.values.reduce(0, +)
                VStack(spacing: 7) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ForEach(Area.all) { a in
                            if let s = d.perArea[a.id], s > 0 {
                                Rectangle().fill(a.tint)
                                    .frame(height: CGFloat(s) / CGFloat(maxV) * 110)
                            }
                        }
                    }
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .background(Palette.sunk)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(String(Sv.weekday(d.key).prefix(2)).lowercased())
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(d.key == DayKey.today ? Palette.label : Palette.third)
                }
                .opacity(total == 0 ? 0.55 : 1)
            }
        }
    }

    private var balance: some View {
        let per = Dictionary(grouping: days.flatMap { $0.perArea.map { ($0.key, $0.value) } }, by: \.0)
            .mapValues { $0.reduce(0) { $0 + $1.1 } }
        let top = max(1, per.values.max() ?? 1)
        return VStack(spacing: 11) {
            ForEach(Area.all) { a in
                let v = per[a.id] ?? 0
                HStack(spacing: 11) {
                    Text(a.name).font(.system(size: 13)).foregroundStyle(Palette.second)
                        .frame(width: 100, alignment: .leading).lineLimit(1)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.sunk)
                            Capsule().fill(a.tint)
                                .frame(width: g.size.width * CGFloat(v) / CGFloat(top))
                        }
                    }
                    .frame(height: 8)
                    Text(v > 0 ? Sv.short(seconds: v) : "—")
                        .font(Typo.meta).foregroundStyle(Palette.third)
                        .frame(width: 46, alignment: .trailing).monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder private var sessions: some View {
        if store.s.sessions.isEmpty {
            Text("Inga pass ännu. Starta din första timer så dyker den upp här.")
                .font(.system(size: 14)).foregroundStyle(Palette.third)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(store.s.sessions.prefix(12).enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 11) {
                        Circle().fill(Area.of(s.areaID)?.tint ?? Palette.inbox).frame(width: 8, height: 8)
                        Text(s.title).font(.system(size: 14)).lineLimit(1)
                        Spacer()
                        Text("\(Sv.short(seconds: s.seconds)) · \(s.endedAt.formatted(date: .omitted, time: .shortened))")
                            .font(Typo.meta).foregroundStyle(Palette.third).monospacedDigit()
                    }
                    .padding(.vertical, 9)
                    if i < min(11, store.s.sessions.count - 1) { Hairline() }
                }
            }
        }
    }
}
