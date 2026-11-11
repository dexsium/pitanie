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
                enabled: true, day: todayKey(), kcal: 1200, kcalGoal: 2000, p: 70, pGoal: 120,
                f: 40, fGoal: 65, c: 140, cGoal: 250, water: 900, waterGoal: 2000))
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

private let accent = Color(red: 0.42, green: 0.30, blue: 0.95)

private func n(_ v: Double) -> String { String(Int(max(0, v).rounded())) }

private struct Bar: View {
    let value: Double
    let goal: Double
    let color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule().fill(color)
                    .frame(width: g.size.width * CGFloat(goal > 0 ? min(1, value / goal) : 0))
            }
        }
        .frame(height: 6)
    }
}

extension View {
    @ViewBuilder
    fileprivate func pwBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { Color(UIColor.secondarySystemBackground) }
        } else {
            self.padding().background(Color(UIColor.secondarySystemBackground))
        }
    }
}

struct PitanieWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PitanieEntry

    var body: some View {
        Group {
            if let s = entry.snap, s.enabled, s.day == todayKey() {
                content(s)
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

    @ViewBuilder
    private func content(_ s: DaySnapshot) -> some View {
        let left = s.kcalGoal - s.kcal
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(left >= 0 ? n(left) : "+" + n(-left))
                    .font(.system(size: family == .systemSmall ? 28 : 32, weight: .bold))
                Text(left >= 0 ? "ккал осталось" : "ккал сверх нормы")
                    .font(.caption).foregroundColor(.secondary)
            }
            Bar(value: s.kcal, goal: s.kcalGoal, color: accent)
            Text("\(n(s.kcal)) из \(n(s.kcalGoal)) ккал")
                .font(.caption).foregroundColor(.secondary)
            if family != .systemSmall {
                HStack {
                    Text("Б \(n(s.p))/\(n(s.pGoal))")
                    Spacer()
                    Text("Ж \(n(s.f))/\(n(s.fGoal))")
                    Spacer()
                    Text("У \(n(s.c))/\(n(s.cGoal))")
                }
                .font(.caption)
                Text("Вода \(n(s.water)) из \(n(s.waterGoal)) мл")
                    .font(.caption).foregroundColor(.secondary)
                Bar(value: s.water, goal: s.waterGoal, color: .blue)
                HStack(spacing: 8) {
                    actionLink("Вода", "water")
                    actionLink("Питание", "nutrition")
                    actionLink("Вес", "weight")
                }
            }
        }
        .widgetURL(URL(string: "pitanie://widget/nutrition"))
    }

    private func actionLink(_ title: String, _ action: String) -> some View {
        Link(destination: URL(string: "pitanie://widget/\(action)")!) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(accent.opacity(0.14))
                .cornerRadius(10)
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
