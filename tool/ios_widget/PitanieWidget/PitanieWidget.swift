// Виджет «Питание» для iOS (WidgetKit): остаток калорий, БЖУ и вода за сегодня.
// Данные берутся из общей группы приложений, куда их кладёт приложение (плагин pitanie_widgets).
// Виджет только читает готовый снимок: в сеть не ходит, рекламе и аналитике ничего не передаёт.
// Поддерживаются только малый и средний размер: на экране блокировки виджет не показывается.
import SwiftUI
import WidgetKit

private let appGroup = "group.com.pitanie.pitanie"
private let snapshotKey = "pitanie_widget_snapshot"

struct DaySnapshot {
    let enabled: Bool
    let day: String
    let kcal: Double
    let kcalGoal: Double
    let p: Double
    let pGoal: Double
    let f: Double
    let fGoal: Double
    let c: Double
    let cGoal: Double
    let water: Double
    let waterGoal: Double
}

private func todayKey() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

private func loadSnapshot() -> DaySnapshot? {
    guard let json = UserDefaults(suiteName: appGroup)?.string(forKey: snapshotKey),
        let data = json.data(using: .utf8),
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    func num(_ k: String) -> Double { (obj[k] as? NSNumber)?.doubleValue ?? 0 }
    return DaySnapshot(
        enabled: (obj["enabled"] as? Bool) ?? false,
        day: (obj["day"] as? String) ?? "",
        kcal: num("kcal"), kcalGoal: num("kcalGoal"),
        p: num("p"), pGoal: num("pGoal"),
        f: num("f"), fGoal: num("fGoal"),
        c: num("c"), cGoal: num("cGoal"),
        water: num("water"), waterGoal: num("waterGoal"))
}

struct PitanieEntry: TimelineEntry {
    let date: Date
    let snap: DaySnapshot?
}

struct PitanieProvider: TimelineProvider {
    func placeholder(in context: Context) -> PitanieEntry {
        PitanieEntry(
            date: Date(),
            snap: DaySnapshot(
                enabled: true, day: todayKey(), kcal: 789, kcalGoal: 2456, p: 38, pGoal: 140,
                f: 57, fGoal: 63, c: 31, cGoal: 332, water: 250, waterGoal: 2300))
    }

    func getSnapshot(in context: Context, completion: @escaping (PitanieEntry) -> Void) {
        completion(PitanieEntry(date: Date(), snap: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PitanieEntry>) -> Void) {
        let entry = PitanieEntry(date: Date(), snap: loadSnapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Оформление в стиле приложения

private func dyn(_ light: UIColor, _ dark: UIColor) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

private let accent = dyn(
    UIColor(red: 0.486, green: 0.227, blue: 0.929, alpha: 1),
    UIColor(red: 0.635, green: 0.482, blue: 1.0, alpha: 1))
private let orange = dyn(
    UIColor(red: 1.0, green: 0.54, blue: 0.0, alpha: 1),
    UIColor(red: 1.0, green: 0.66, blue: 0.30, alpha: 1))
private let blue = dyn(
    UIColor(red: 0.12, green: 0.48, blue: 0.97, alpha: 1),
    UIColor(red: 0.35, green: 0.69, blue: 1.0, alpha: 1))
private let bgColor = dyn(
    UIColor(red: 0.969, green: 0.961, blue: 1.0, alpha: 1),
    UIColor(red: 0.110, green: 0.110, blue: 0.149, alpha: 1))
private let chipColor = dyn(
    UIColor.white,
    UIColor(red: 0.149, green: 0.149, blue: 0.2, alpha: 1))
private let trackColor = dyn(
    UIColor(red: 0.855, green: 0.847, blue: 0.91, alpha: 1),
    UIColor(red: 0.227, green: 0.227, blue: 0.29, alpha: 1))
private let pillColor = dyn(
    UIColor(red: 0.933, green: 0.91, blue: 1.0, alpha: 1),
    UIColor(red: 0.18, green: 0.157, blue: 0.251, alpha: 1))
private let pillStroke = dyn(
    UIColor(red: 0.831, green: 0.776, blue: 0.98, alpha: 1),
    UIColor(red: 0.29, green: 0.247, blue: 0.42, alpha: 1))

private func n(_ v: Double) -> String { String(Int(max(0, v).rounded())) }

private struct Bar: View {
    let value: Double
    let goal: Double
    let color: Color
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule().fill(color)
                    .frame(width: g.size.width * CGFloat(goal > 0 ? min(1, value / goal) : 0))
            }
        }
        .frame(height: height)
    }
}

private struct RoundIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.16)))
    }
}

private struct MacroChip: View {
    let symbol: String
    let letter: String
    let value: Double
    let goal: Double
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            RoundIcon(symbol: symbol, color: color, size: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(letter) \(n(value))/\(n(goal)) г")
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Bar(value: value, goal: goal, color: color, height: 4)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(chipColor))
    }
}

extension View {
    @ViewBuilder
    fileprivate func pwBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { bgColor }
        } else {
            self.padding(12).background(bgColor)
        }
    }
}

struct PitanieWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PitanieEntry

    var body: some View {
        Group {
            if let s = entry.snap, s.enabled, s.day == todayKey() {
                if family == .systemSmall { small(s) } else { medium(s) }
            } else {
                Text(
                    (entry.snap?.enabled ?? false)
                        ? "Откройте приложение, чтобы обновить данные"
                        : "Данные в виджетах выключены. Включите их в настройках приложения."
                )
                .font(.footnote)
                .foregroundColor(.secondary)
                .widgetURL(URL(string: "pitanie://widget/settings"))
            }
        }
        .pwBackground()
    }

    private func header(_ s: DaySnapshot, bigSize: CGFloat, icon: CGFloat) -> some View {
        let left = s.kcalGoal - s.kcal
        return HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: icon * 0.55, weight: .bold))
                .foregroundColor(.white)
                .frame(width: icon, height: icon)
                .background(RoundedRectangle(cornerRadius: icon * 0.32).fill(accent))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(left >= 0 ? n(left) : "+" + n(-left))
                        .font(.system(size: bigSize, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(left >= 0 ? "ккал осталось" : "ккал сверх")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text("\(n(s.kcal)) из \(n(s.kcalGoal)) ккал")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
    }

    private func waterRow(_ s: DaySnapshot, withPercent: Bool) -> some View {
        let pct = s.waterGoal > 0 ? Int(min(1, s.water / s.waterGoal) * 100) : 0
        return HStack(spacing: 6) {
            Image(systemName: "drop.fill").font(.system(size: 12)).foregroundColor(blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("Вода \(n(s.water)) из \(n(s.waterGoal)) мл")
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Bar(value: s.water, goal: s.waterGoal, color: blue, height: 4)
            }
            if withPercent {
                Text("\(pct)%")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(pillColor))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 12).fill(chipColor))
    }

    @ViewBuilder
    private func small(_ s: DaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(s, bigSize: 22, icon: 30)
            Bar(value: s.kcal, goal: s.kcalGoal, color: accent, height: 6)
            Spacer(minLength: 0)
            waterRow(s, withPercent: false)
        }
        .widgetURL(URL(string: "pitanie://widget/nutrition"))
    }

    @ViewBuilder
    private func medium(_ s: DaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            header(s, bigSize: 24, icon: 30)
            Bar(value: s.kcal, goal: s.kcalGoal, color: accent, height: 6)
            HStack(spacing: 5) {
                MacroChip(symbol: "dumbbell.fill", letter: "Б", value: s.p, goal: s.pGoal, color: accent)
                MacroChip(symbol: "drop.fill", letter: "Ж", value: s.f, goal: s.fGoal, color: orange)
                MacroChip(symbol: "leaf.fill", letter: "У", value: s.c, goal: s.cGoal, color: blue)
            }
            waterRow(s, withPercent: true)
            HStack(spacing: 5) {
                actionLink("Вода", "drop", "water")
                actionLink("Питание", "fork.knife", "nutrition")
                actionLink("Вес", "scalemass", "weight")
            }
        }
        .widgetURL(URL(string: "pitanie://widget/nutrition"))
    }

    private func actionLink(_ title: String, _ symbol: String, _ action: String) -> some View {
        Link(destination: URL(string: "pitanie://widget/\(action)")!) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Capsule().fill(pillColor))
            .overlay(Capsule().stroke(pillStroke, lineWidth: 1))
        }
    }
}

@main
struct PitanieWidget: Widget {
    let kind = "PitanieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PitanieProvider()) { entry in
            PitanieWidgetView(entry: entry)
        }
        .configurationDisplayName("Питание")
        .description("Калории, белки, жиры, углеводы и вода за сегодня")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
