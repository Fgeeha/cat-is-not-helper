import Foundation
import Combine

struct DayStats: Codable {
    var keys = 0
    var clicks = 0
    var hourly = [Int](repeating: 0, count: 24)
}

struct StatsData: Codable {
    var days: [String: DayStats] = [:]
    var totalKeys = 0
    var totalClicks = 0
    var pets = 0
    var feeds = 0
    var screenshots = 0
    var bestCPM = 0
    var firstLaunch = Date()
}

struct DayPoint: Identifiable {
    let id: String
    let label: String
    let keys: Int
    let isToday: Bool
}

/// Хранит статистику тапов в ~/Library/Application Support/CatIsNotHelper/stats.json
final class StatsStore: ObservableObject {
    @Published private(set) var data = StatsData()
    @Published private(set) var cpm = 0
    @Published private(set) var sessionKeys = 0

    private var recent: [Date] = []
    private var dirty = false
    private var lastSave = Date.distantPast
    private let fileURL: URL

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "dd.MM"
        return f
    }()

    static let longDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("CatIsNotHelper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("stats.json")
    }

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

    // MARK: - Загрузка / сохранение

    func load() {
        guard let raw = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(StatsData.self, from: raw) else { return }
        data = decoded
    }

    func save() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: fileURL, options: .atomic)
        dirty = false
        lastSave = Date()
    }

    // MARK: - Запись событий

    func recordKey() {
        let now = Date()
        let key = Self.dayKey(now)
        var day = data.days[key] ?? DayStats()
        day.keys += 1
        day.hourly[Calendar.current.component(.hour, from: now)] += 1
        data.days[key] = day
        data.totalKeys += 1
        sessionKeys += 1
        recent.append(now)
        trimRecent(now)
        cpm = recent.count
        if cpm > data.bestCPM { data.bestCPM = cpm }
        dirty = true
    }

    func recordClick() {
        let key = Self.dayKey(Date())
        var day = data.days[key] ?? DayStats()
        day.clicks += 1
        data.days[key] = day
        data.totalClicks += 1
        dirty = true
    }

    func recordPet() { data.pets += 1; dirty = true }
    func recordFeed() { data.feeds += 1; dirty = true }
    func recordScreenshot() { data.screenshots += 1; dirty = true }

    func tick() {
        let now = Date()
        trimRecent(now)
        if recent.count != cpm { cpm = recent.count }
        if dirty, now.timeIntervalSince(lastSave) > 3 { save() }
    }

    private func trimRecent(_ now: Date) {
        let cutoff = now.addingTimeInterval(-60)
        if let idx = recent.firstIndex(where: { $0 > cutoff }) {
            if idx > 0 { recent.removeFirst(idx) }
        } else {
            recent.removeAll()
        }
    }

    // MARK: - Агрегаты

    var today: DayStats { data.days[Self.dayKey(Date())] ?? DayStats() }

    var last14: [DayPoint] {
        let cal = Calendar.current
        let todayKey = Self.dayKey(Date())
        return (0..<14).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = Self.dayKey(date)
            return DayPoint(id: key,
                            label: Self.shortDayFormatter.string(from: date),
                            keys: data.days[key]?.keys ?? 0,
                            isToday: key == todayKey)
        }
    }

    var bestDay: (label: String, keys: Int)? {
        guard let best = data.days.max(by: { $0.value.keys < $1.value.keys }), best.value.keys > 0,
              let date = Self.dayFormatter.date(from: best.key) else { return nil }
        return (Self.shortDayFormatter.string(from: date), best.value.keys)
    }

    var activeDays: Int { data.days.values.filter { $0.keys > 0 }.count }

    var averagePerActiveDay: Int {
        let days = activeDays
        return days == 0 ? 0 : data.totalKeys / days
    }

    /// Сколько дней подряд (включая сегодня или вчера) котик тапал.
    var streak: Int {
        let cal = Calendar.current
        var date = Date()
        if (data.days[Self.dayKey(date)]?.keys ?? 0) == 0 {
            guard let y = cal.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = y
        }
        var count = 0
        while (data.days[Self.dayKey(date)]?.keys ?? 0) > 0 {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        return count
    }
}
