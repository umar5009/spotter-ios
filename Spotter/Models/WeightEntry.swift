import Foundation
import SwiftData

/// A body-weight weigh-in. This is separate from the load used on a lift.
@Model
final class WeightEntry {
    var id: UUID
    var date: Date
    var weightKg: Double

    init(id: UUID = UUID(), date: Date = .now, weightKg: Double) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
    }
}

enum WeightTrend {
    struct Snapshot {
        var latest: WeightEntry?
        var weekDelta: Double?
        var monthDelta: Double?
        var sorted: [WeightEntry]
    }

    static func snapshot(from entries: [WeightEntry], now: Date = .now, calendar: Calendar = .current) -> Snapshot {
        let sorted = entries.sorted { $0.date < $1.date }
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let monthStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        return Snapshot(
            latest: sorted.last,
            weekDelta: delta(sorted, since: weekStart),
            monthDelta: delta(sorted, since: monthStart),
            sorted: sorted
        )
    }

    /// Latest weight minus the weigh-in from the start of the window.
    /// Negative means weight went down.
    private static func delta(_ sorted: [WeightEntry], since start: Date) -> Double? {
        guard let latest = sorted.last else { return nil }
        if let baseline = sorted.last(where: { $0.date <= start }), baseline.id != latest.id {
            return latest.weightKg - baseline.weightKg
        }
        guard let first = sorted.first(where: { $0.date > start }), first.id != latest.id else { return nil }
        return latest.weightKg - first.weightKg
    }

    static func kg(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func changeLabel(_ delta: Double?, unit: Measure.Weight) -> String {
        guard let delta else { return String(localized: "Not enough weigh-ins") }
        let shown = abs(unit.fromKilograms(delta))
        if shown < 0.1 { return String(localized: "No change") }
        let amount = Measure.format(shown)
        return delta < 0
            ? String(localized: "\(amount) \(unit.symbol) lost")
            : String(localized: "\(amount) \(unit.symbol) gained")
    }
}

/// Body mass index from weight in kilograms and height in centimetres.
enum BMI {
    struct Result {
        var value: Double
        var category: Category
    }

    enum Category: String {
        case underweight = "Underweight"
        case healthy = "Healthy"
        case overweight = "Overweight"
        case obese = "Obese"

        /// Healthy is the 18.5–24.9 band used by the standard adult chart.
        var isHealthy: Bool { self == .healthy }
    }

    static func calculate(weightKg: Double, heightCm: Double) -> Result? {
        guard (20...400).contains(weightKg), (90...250).contains(heightCm) else { return nil }
        let meters = heightCm / 100
        let value = weightKg / (meters * meters)
        guard value.isFinite else { return nil }
        return Result(value: value, category: category(for: value))
    }

    static func category(for value: Double) -> Category {
        switch value {
        case ..<18.5: return .underweight
        case ..<25: return .healthy
        case ..<30: return .overweight
        default: return .obese
        }
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func weightKg(for bmi: Double, heightCm: Double) -> Double {
        let meters = heightCm / 100
        return bmi * meters * meters
    }
}

/// Where the user's weight sits against the healthy range for their height.
enum BodyRange {
    static let scaleMin = 15.0
    static let scaleMax = 40.0
    static let healthyLowBMI = 18.5
    static let healthyHighBMI = 24.9
    static let overweightHighBMI = 29.9

    struct Report {
        var bmi: Double
        var category: BMI.Category
        var healthyLowKg: Double
        var healthyHighKg: Double
        /// 0...1 across the chart, from BMI 15 to 40.
        var marker: Double
        var goalMarker: Double?
        var verdict: String
        var detail: String
        var tone: Tone
    }

    enum Tone {
        case under, healthy, over, high
    }

    struct Segment: Identifiable {
        let id: String
        let title: String
        let tone: Tone
        let fraction: Double
    }

    static let segments: [Segment] = {
        let span = scaleMax - scaleMin
        return [
            Segment(id: "under", title: String(localized: "Under"), tone: .under, fraction: (healthyLowBMI - scaleMin) / span),
            Segment(id: "healthy", title: String(localized: "In range"), tone: .healthy, fraction: (healthyHighBMI - healthyLowBMI) / span),
            Segment(id: "over", title: String(localized: "Over"), tone: .over, fraction: (overweightHighBMI - healthyHighBMI) / span),
            Segment(id: "high", title: String(localized: "High"), tone: .high, fraction: (scaleMax - overweightHighBMI) / span)
        ]
    }()

    static func healthyWeightKg(heightCm: Double) -> (low: Double, high: Double)? {
        guard (90...250).contains(heightCm) else { return nil }
        return (BMI.weightKg(for: healthyLowBMI, heightCm: heightCm),
                BMI.weightKg(for: healthyHighBMI, heightCm: heightCm))
    }

    static func assess(weightKg: Double, heightCm: Double, goalKg: Double = 0, unit: Measure.Weight) -> Report? {
        guard let result = BMI.calculate(weightKg: weightKg, heightCm: heightCm),
              let band = healthyWeightKg(heightCm: heightCm) else { return nil }

        let clamped = min(max(result.value, scaleMin), scaleMax)
        let marker = (clamped - scaleMin) / (scaleMax - scaleMin)
        let range = "\(amount(band.low, unit))–\(amount(band.high, unit)) \(unit.symbol)"
        let tone: Tone
        let verdict: String
        var detail: String

        if result.value < healthyLowBMI {
            tone = .under
            verdict = String(localized: "Under your range")
            let below = band.low - weightKg
            detail = String(localized: "A healthy weight for your height is \(range). You are \(amount(below, unit)) \(unit.symbol) below it, so you do not need to lose more.")
        } else if result.value < 25 {
            tone = .healthy
            verdict = String(localized: "In a healthy range")
            detail = String(localized: "A healthy weight for your height is \(range). Your weight is inside it.")
        } else {
            tone = result.value < 30 ? .over : .high
            verdict = String(localized: "Over your range")
            let above = weightKg - band.high
            detail = String(localized: "A healthy weight for your height is \(range). You are \(amount(above, unit)) \(unit.symbol) above it.")
        }

        if goalKg > 0 {
            detail += " " + goalSentence(weightKg: weightKg, goalKg: goalKg, healthyLowKg: band.low, unit: unit)
        }

        var goalMarker: Double?
        if goalKg > 0, let goalBMI = BMI.calculate(weightKg: goalKg, heightCm: heightCm)?.value {
            let clampedGoal = min(max(goalBMI, scaleMin), scaleMax)
            goalMarker = (clampedGoal - scaleMin) / (scaleMax - scaleMin)
        }

        return Report(bmi: result.value, category: result.category, healthyLowKg: band.low, healthyHighKg: band.high,
                      marker: marker, goalMarker: goalMarker, verdict: verdict, detail: detail, tone: tone)
    }

    private static func goalSentence(weightKg: Double, goalKg: Double, healthyLowKg: Double, unit: Measure.Weight) -> String {
        if goalKg < healthyLowKg - 0.2 {
            return String(localized: "Your goal of \(amount(goalKg, unit)) \(unit.symbol) is below that healthy range.")
        }
        let gap = weightKg - goalKg
        if gap > 0.15 {
            return String(localized: "You still have \(amount(gap, unit)) \(unit.symbol) to lose to reach your \(amount(goalKg, unit)) \(unit.symbol) goal.")
        }
        if gap < -0.15 {
            return String(localized: "You are already under your \(amount(goalKg, unit)) \(unit.symbol) goal.")
        }
        return String(localized: "You are at your \(amount(goalKg, unit)) \(unit.symbol) goal.")
    }

    private static func amount(_ kg: Double, _ unit: Measure.Weight) -> String {
        Measure.format(unit.fromKilograms(max(0, kg)))
    }
}
