import SwiftUI
import Charts

struct StatsView: View {
    @ObservedObject var stats: StatsStore
    @ObservedObject var state: CatState
    @ObservedObject var shots: ScreenshotManager

    private let accent = Color(red: 0.93, green: 0.55, blue: 0.2)

    var body: some View {
        ScrollView {
            content
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 620)
    }

    var content: some View {
            VStack(alignment: .leading, spacing: 20) {
                header

                HStack(spacing: 12) {
                    StatCard(title: "Сегодня", value: stats.today.keys.formatted(), hint: "тапов")
                    StatCard(title: "Сейчас", value: "\(stats.cpm)", hint: "нажатий в минуту")
                    StatCard(title: "Всего", value: stats.data.totalKeys.formatted(), hint: "за всё время")
                }
                HStack(spacing: 12) {
                    StatCard(title: "Рекорд скорости", value: "\(stats.data.bestCPM)", hint: "в минуту")
                    StatCard(title: "Серия", value: "\(stats.streak)", hint: stats.streak == 1 ? "день подряд" : "дней подряд")
                    StatCard(title: "Клики мышью", value: stats.data.totalClicks.formatted(), hint: "сегодня: \(stats.today.clicks)")
                }

                section("Последние 14 дней") {
                    Chart(stats.last14) { day in
                        BarMark(x: .value("День", day.label), y: .value("Тапы", day.keys), width: .ratio(0.6))
                            .foregroundStyle(day.isToday ? accent : accent.opacity(0.45))
                            .cornerRadius(4)
                    }
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
                    .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.caption2) } }
                    .frame(height: 170)
                    if let best = stats.bestDay {
                        Text("Лучший день: \(best.label) — \(best.keys.formatted()) тапов. В среднем за активный день: \(stats.averagePerActiveDay.formatted()).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                section("Сегодня по часам") {
                    Chart(Array(stats.today.hourly.enumerated()), id: \.offset) { item in
                        BarMark(x: .value("Час", String(format: "%02d", item.offset)), y: .value("Тапы", item.element), width: .ratio(0.6))
                            .foregroundStyle(accent.opacity(0.8))
                            .cornerRadius(3)
                    }
                    .chartXAxis { AxisMarks(values: ["00", "03", "06", "09", "12", "15", "18", "21"]) { _ in AxisValueLabel().font(.caption2) } }
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
                    .frame(height: 150)
                }

                section("Котик") {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Настроение: \(moodEmoji(state.mood)) \(moodTitle(state.mood))")
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.15))
                                    Capsule().fill(accent).frame(width: max(8, geo.size.width * state.happiness))
                                }
                            }
                            .frame(height: 10)
                            Text("Счастье: \(Int(state.happiness * 100))%").font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Погладили: \(stats.data.pets)")
                            Text("Покормили: \(stats.data.feeds)")
                            Text("Скриншотов дали: \(stats.data.screenshots)")
                            Text("В галерее: \(shots.items.count)")
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let held = state.heldURL {
                        Text(state.heldStack.count > 1
                             ? "Сейчас держит \(state.heldStack.count) файлов, сверху: \(held.lastPathComponent)"
                             : "Сейчас держит: \(held.lastPathComponent)")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("Сейчас лапки свободны — дай ему скриншот.").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Статистика котика").font(.title2.bold())
            Spacer()
            Text("с \(StatsStore.longDayFormatter.string(from: stats.data.firstLaunch))")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(hint).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
