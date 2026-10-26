import Foundation

/// Ranks Spotter can award from workouts, streaks, form, and a weight-loss target.
/// A badge stays once the best result qualifies. A broken streak does not take it back.
enum SpotterBadge: String, CaseIterable, Identifiable {
    case beginnerChamp
    case steadyChamp
    case weekChamp
    case formChamp
    case superChamp
    case ironChamp
    case goalWeight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginnerChamp: return String(localized: "Beginner Champ")
        case .steadyChamp: return String(localized: "Steady Champ")
        case .weekChamp: return String(localized: "Week Champ")
        case .formChamp: return String(localized: "Form Champ")
        case .superChamp: return String(localized: "Super Champ")
        case .ironChamp: return String(localized: "Iron Champ")
        case .goalWeight: return String(localized: "Goal Weight")
        }
    }

    var symbol: String {
        switch self {
        case .beginnerChamp: return "figure.walk"
        case .steadyChamp: return "figure.run"
        case .weekChamp: return "calendar"
        case .formChamp: return "checkmark.seal.fill"
        case .superChamp: return "star.fill"
        case .ironChamp: return "flame.fill"
        case .goalWeight: return "seal.fill"
        }
    }

    /// Champ ranks, in order. Form and the weight goal sit beside this ladder.
    var isRank: Bool {
        switch self {
        case .formChamp, .goalWeight: return false
        default: return true
        }
    }

    var requirement: String {
        switch self {
        case .beginnerChamp: return String(localized: "Finish 1 coached workout.")
        case .steadyChamp: return String(localized: "Finish 5 coached workouts.")
        case .weekChamp: return String(localized: "Train 7 days in a row.")
        case .formChamp: return String(localized: "Score 85 or higher on 5 workouts.")
        case .superChamp: return String(localized: "Train 14 days in a row.")
        case .ironChamp: return String(localized: "Train 30 days in a row.")
        case .goalWeight: return String(localized: "Set a loss target, then weigh in at or under it.")
        }
    }
}

struct BadgeStanding: Identifiable {
    var badge: SpotterBadge
    var earned: Bool
    var fraction: Double
    var progress: String

    var id: String { badge.rawValue }
}

struct BadgeReport {
    var standings: [BadgeStanding]
    /// Highest champ rank earned. Goal Weight only fills this when no rank is earned yet.
    var current: SpotterBadge?
    var next: BadgeStanding?
    var summary: String
}

enum BadgeBoard {
    /// Form at this score is the same "sharp" bar the rest of the app treats as good.
    static let sharpForm = 85

    static func report(
        logs: [WorkoutLog],
        weights: [WeightEntry],
        goalKg: Double,
        startKg: Double,
        cadence: LossCadence,
        periodKg: Double
    ) -> BadgeReport {
        let workouts = logs.count
        let best = Streak.longest(from: logs.map(\.date))
        let streak = Streak.current(from: logs.map(\.date))
        let sharp = logs.filter { $0.avgFormScore >= sharpForm }.count
        let scored = logs.filter { $0.avgFormScore > 0 }
        let form = scored.isEmpty ? 0 : scored.reduce(0) { $0 + $1.avgFormScore } / scored.count
        let loss = WeightLoss.status(entries: weights, goalKg: goalKg, startKg: startKg, cadence: cadence, periodKg: periodKg)

        let standings = SpotterBadge.allCases.map { badge in
            standing(badge, workouts: workouts, bestStreak: best, sharp: sharp, loss: loss, hasTarget: goalKg > 0)
        }
        let current = standings.last { $0.earned && $0.badge.isRank }?.badge
            ?? standings.first { $0.badge == .goalWeight && $0.earned }?.badge
        let summary = stateLine(workouts: workouts, streak: streak, form: form, scored: !scored.isEmpty)
        return BadgeReport(standings: standings, current: current, next: standings.first { !$0.earned }, summary: summary)
    }

    private static func standing(
        _ badge: SpotterBadge,
        workouts: Int,
        bestStreak: Int,
        sharp: Int,
        loss: WeightLoss.Status?,
        hasTarget: Bool
    ) -> BadgeStanding {
        switch badge {
        case .beginnerChamp:
            return count(badge, value: workouts, needed: 1, unit: String(localized: "workout"))
        case .steadyChamp:
            return count(badge, value: workouts, needed: 5, unit: String(localized: "workouts"))
        case .weekChamp:
            return count(badge, value: bestStreak, needed: 7, unit: String(localized: "days"))
        case .formChamp:
            return count(badge, value: sharp, needed: 5, unit: String(localized: "sharp sessions"))
        case .superChamp:
            return count(badge, value: bestStreak, needed: 14, unit: String(localized: "days"))
        case .ironChamp:
            return count(badge, value: bestStreak, needed: 30, unit: String(localized: "days"))
        case .goalWeight:
            guard hasTarget, let loss else {
                return BadgeStanding(badge: badge, earned: false, fraction: 0, progress: String(localized: "Set a loss target"))
            }
            let earned = loss.reached
            let progress = earned
                ? String(localized: "Earned")
                : String(localized: "\(Int((loss.fraction * 100).rounded()))% of the goal")
            return BadgeStanding(badge: badge, earned: earned, fraction: earned ? 1 : loss.fraction, progress: progress)
        }
    }

    private static func count(_ badge: SpotterBadge, value: Int, needed: Int, unit: String) -> BadgeStanding {
        let earned = value >= needed
        let shown = min(value, needed)
        let progress = earned ? String(localized: "Earned") : String(localized: "\(shown) of \(needed) \(unit)")
        let fraction = needed == 0 ? 0 : min(1, Double(value) / Double(needed))
        return BadgeStanding(badge: badge, earned: earned, fraction: fraction, progress: progress)
    }

    private static func stateLine(workouts: Int, streak: Int, form: Int, scored: Bool) -> String {
        let sessions = workouts == 1
            ? String(localized: "1 workout")
            : String(localized: "\(workouts) workouts")
        let run = streak == 1
            ? String(localized: "1-day streak")
            : String(localized: "\(streak)-day streak")
        if scored {
            return String(localized: "\(sessions) · \(run) · form \(form)")
        }
        return String(localized: "\(sessions) · \(run)")
    }
}
