import Foundation

/// How often a loss is celebrated before the final goal.
enum LossCadence: String, CaseIterable, Identifiable {
    case week, month

    var id: String { rawValue }

    var title: String {
        self == .week ? String(localized: "Weekly") : String(localized: "Monthly")
    }

    var periodName: String {
        self == .week ? String(localized: "This week") : String(localized: "This month")
    }

    var targetField: String {
        self == .week ? String(localized: "Lose each week") : String(localized: "Lose each month")
    }
}

/// Progress from a starting weigh-in down to a goal weight.
enum WeightLoss {
    static let startKey = "lossStartKg"
    static let cadenceKey = "lossCadence"
    static let periodKey = "lossPeriodKg"
    static let cheerKey = "lossCheerPeriod"
    static let badgeKey = "lossBadgeGoalKg"

    struct Status {
        var currentKg: Double?
        var startKg: Double
        var goalKg: Double
        var fraction: Double
        var lostKg: Double
        var remainingKg: Double
        var periodDelta: Double?
        var cadence: LossCadence
        var periodTargetKg: Double
        var reached: Bool
    }

    enum Celebration: Equatable, Identifiable {
        case badge(goalKg: Double)
        case period(cadence: LossCadence, lostKg: Double, hitTarget: Bool)

        var id: String {
            switch self {
            case .badge: return "badge"
            case .period(let cadence, _, _): return "period-\(cadence.rawValue)"
            }
        }
    }

    static var badgeEarned: Bool {
        UserDefaults.standard.double(forKey: badgeKey) > 0
    }

    static func status(entries: [WeightEntry], goalKg: Double, startKg: Double, cadence: LossCadence, periodKg: Double, now: Date = .now) -> Status? {
        guard goalKg > 0 else { return nil }
        let snap = WeightTrend.snapshot(from: entries, now: now)
        let current = snap.latest?.weightKg
        let start = startKg > 0 ? startKg : (snap.sorted.first?.weightKg ?? current ?? goalKg)
        let span = start - goalKg
        let lost = max(0, start - (current ?? start))
        let fraction: Double
        let reached: Bool
        if let current, span > 0.05 {
            fraction = min(1, max(0, lost / span))
            reached = current <= goalKg + 0.05
        } else {
            fraction = 0
            reached = false
        }
        let remaining = max(0, (current ?? start) - goalKg)
        let periodDelta = cadence == .week ? snap.weekDelta : snap.monthDelta
        return Status(
            currentKg: current,
            startKg: start,
            goalKg: goalKg,
            fraction: fraction,
            lostKg: lost,
            remainingKg: remaining,
            periodDelta: periodDelta,
            cadence: cadence,
            periodTargetKg: periodKg,
            reached: reached
        )
    }

    /// Awards a badge or a period win once, then returns what to show.
    static func claim(entries: [WeightEntry], goalKg: Double, startKg: Double, cadence: LossCadence, periodKg: Double, now: Date = .now) -> Celebration? {
        guard let status = status(entries: entries, goalKg: goalKg, startKg: startKg, cadence: cadence, periodKg: periodKg, now: now),
              status.currentKg != nil else { return nil }

        let earnedFor = UserDefaults.standard.double(forKey: badgeKey)
        if status.reached, abs(earnedFor - status.goalKg) > 0.05 {
            UserDefaults.standard.set(status.goalKg, forKey: badgeKey)
            UserDefaults.standard.set(periodStamp(cadence, now: now), forKey: cheerKey)
            SpotterAnalytics.log("loss_badge", ["id": "goal-weight"])
            return .badge(goalKg: status.goalKg)
        }

        let stamp = periodStamp(cadence, now: now)
        guard UserDefaults.standard.string(forKey: cheerKey) != stamp else { return nil }
        guard let delta = status.periodDelta else { return nil }
        let needed = status.periodTargetKg > 0 ? status.periodTargetKg : 0.1
        guard delta <= -needed else { return nil }
        UserDefaults.standard.set(stamp, forKey: cheerKey)
        SpotterAnalytics.log("loss_period", [
            "cadence": cadence.rawValue,
            "hit_target": status.periodTargetKg > 0 ? "true" : "false"
        ])
        return .period(cadence: cadence, lostKg: abs(delta), hitTarget: status.periodTargetKg > 0)
    }

    static func rememberStart(_ kg: Double, replacing stored: Double, goalChanged: Bool) -> Double {
        if stored <= 0 || goalChanged { return kg }
        return stored
    }

    private static func periodStamp(_ cadence: LossCadence, now: Date, calendar: Calendar = .current) -> String {
        switch cadence {
        case .week:
            let week = calendar.component(.weekOfYear, from: now)
            let year = calendar.component(.yearForWeekOfYear, from: now)
            return "w-\(year)-\(week)"
        case .month:
            let parts = calendar.dateComponents([.year, .month], from: now)
            return "m-\(parts.year ?? 0)-\(parts.month ?? 0)"
        }
    }
}
