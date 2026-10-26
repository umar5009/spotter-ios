import Foundation

/// The load last used for a gym lift, in kilograms.
enum LiftLoad {
    private static let key = "liftLoadKg"

    static func kilograms(for exerciseID: String) -> Double {
        guard let map = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] else { return 0 }
        return map[exerciseID] ?? 0
    }

    static func save(_ kilograms: Double, for exerciseID: String) {
        var map = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        if kilograms > 0 {
            map[exerciseID] = kilograms
        } else {
            map.removeValue(forKey: exerciseID)
        }
        UserDefaults.standard.set(map, forKey: key)
    }

    /// Uses the load on the plan, then the last load saved for that lift.
    static func resolved(_ item: PlannedExercise) -> Double {
        guard ExerciseLibrary.spec(item.exerciseID).category == .gym else { return 0 }
        if let set = item.weightKg, set > 0 { return set }
        return kilograms(for: item.exerciseID)
    }

    static func applying(to items: [PlannedExercise]) -> [PlannedExercise] {
        items.map { item in
            var copy = item
            let load = resolved(item)
            if load > 0 { copy.weightKg = load }
            return copy
        }
    }

    /// One step of the load stepper. The first increase leaves 0 for a usable starting weight.
    static func stepped(_ kilograms: Double, direction: Int, unit: Measure.Weight) -> Double {
        let step = unit.toKilograms(unit.step)
        if kilograms <= 0, direction > 0 {
            let first: Double = unit == .kilograms ? 10 : 20
            return unit.toKilograms(first)
        }
        return max(0, min(500, kilograms + step * Double(direction)))
    }
}

/// The cue Spotter should watch on the next session of each exercise.
enum FaultMemory {
    static func cues(from sets: [SetLog]) -> [String: String] {
        var latest: [String: SetLog] = [:]
        for set in sets {
            if let current = latest[set.exerciseID], current.date >= set.date { continue }
            latest[set.exerciseID] = set
        }
        var watched: [String: String] = [:]
        for (id, set) in latest {
            var counts: [String: Int] = [:]
            for fault in set.faults { counts[fault, default: 0] += 1 }
            if let cue = counts.max(by: { $0.value < $1.value })?.key {
                watched[id] = cue
            }
        }
        return watched
    }
}

/// Exercise order the user chose for one calendar day. Missing means the scheduled plan.
enum DayPlanEdit {
    static func ids(on day: Date, calendar: Calendar = .current) -> [String]? {
        let stored = UserDefaults.standard.stringArray(forKey: key(for: day, calendar: calendar))
        guard let stored, !stored.isEmpty else { return nil }
        return stored
    }

    static func save(_ ids: [String], on day: Date, calendar: Calendar = .current) {
        UserDefaults.standard.set(ids, forKey: key(for: day, calendar: calendar))
        Task { await DayReminder.reschedule() }
    }

    static func clear(on day: Date, calendar: Calendar = .current) {
        UserDefaults.standard.removeObject(forKey: key(for: day, calendar: calendar))
        Task { await DayReminder.reschedule() }
    }

    private static func key(for day: Date, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: day)
        return "planEdit.\(Int(start.timeIntervalSince1970))"
    }
}

/// A repeating weekday focus, such as chest day or leg day.
enum TrainingFocus: String, CaseIterable, Identifiable {
    case chest, back, legs, shoulders, arms, push, pull, fullBody, core, rest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: return String(localized: "Chest")
        case .back: return String(localized: "Back")
        case .legs: return String(localized: "Legs")
        case .shoulders: return String(localized: "Shoulders")
        case .arms: return String(localized: "Arms")
        case .push: return String(localized: "Push")
        case .pull: return String(localized: "Pull")
        case .fullBody: return String(localized: "Full body")
        case .core: return String(localized: "Core")
        case .rest: return String(localized: "Rest")
        }
    }

    var dayName: String {
        switch self {
        case .chest: return String(localized: "Chest day")
        case .back: return String(localized: "Back day")
        case .legs: return String(localized: "Leg day")
        case .shoulders: return String(localized: "Shoulder day")
        case .arms: return String(localized: "Arm day")
        case .push: return String(localized: "Push day")
        case .pull: return String(localized: "Pull day")
        case .fullBody: return String(localized: "Full body day")
        case .core: return String(localized: "Core day")
        case .rest: return String(localized: "Rest day")
        }
    }

    var shortTitle: String {
        switch self {
        case .shoulders: return String(localized: "Delts")
        case .fullBody: return String(localized: "Full")
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .chest: return "figure.strengthtraining.traditional"
        case .back: return "figure.rowing"
        case .legs: return "figure.strengthtraining.functional"
        case .shoulders: return "figure.arms.open"
        case .arms: return "dumbbell.fill"
        case .push: return "arrow.up.circle.fill"
        case .pull: return "arrow.down.circle.fill"
        case .fullBody: return "figure.mixed.cardio"
        case .core: return "figure.core.training"
        case .rest: return "bed.double.fill"
        }
    }

    var detail: String {
        switch self {
        case .chest: return String(localized: "Every chest exercise.")
        case .back: return String(localized: "Every back exercise.")
        case .legs: return String(localized: "Every leg exercise.")
        case .shoulders: return String(localized: "Every shoulder exercise.")
        case .arms: return String(localized: "Every arm exercise.")
        case .push: return String(localized: "Every pushing exercise.")
        case .pull: return String(localized: "Every pulling exercise.")
        case .fullBody: return String(localized: "Every exercise.")
        case .core: return String(localized: "Every core exercise.")
        case .rest: return String(localized: "Easy core and glutes. Move, then stop.")
        }
    }

    func exerciseIDs(place: TrainingPlace) -> [String] {
        _ = place
        switch self {
        case .chest:
            return ["bench", "pushUp", "overheadPress"]
        case .back:
            return ["row", "rdl", "gluteBridge"]
        case .legs:
            return ["squat", "lunge", "gluteBridge", "rdl", "hipThrust"]
        case .shoulders:
            return ["overheadPress", "lateralRaise", "bench", "pushUp"]
        case .arms:
            return ["bicepCurl", "bench", "pushUp", "overheadPress"]
        case .push:
            return ["bench", "pushUp", "overheadPress", "lateralRaise"]
        case .pull:
            return ["row", "rdl", "bicepCurl", "gluteBridge"]
        case .fullBody:
            return ExerciseLibrary.all.map(\.id)
        case .core:
            return ["plank", "gluteBridge", "pushUp"]
        case .rest:
            return ["plank", "gluteBridge"]
        }
    }
}

/// Which focus repeats on each weekday. An empty slot keeps Spotter's own plan for that day.
enum WeekSplit {
    static let storageKey = "weekSplit"

    static func focus(weekday index: Int, in raw: String) -> TrainingFocus? {
        let parts = parts(raw)
        guard parts.indices.contains(index), !parts[index].isEmpty else { return nil }
        return TrainingFocus(rawValue: parts[index])
    }

    static func focus(weekday index: Int) -> TrainingFocus? {
        focus(weekday: index, in: UserDefaults.standard.string(forKey: storageKey) ?? "")
    }

    static func focus(on date: Date) -> TrainingFocus? {
        focus(weekday: PlanBuilder.mondayIndex(date))
    }

    static func set(_ focus: TrainingFocus?, weekday index: Int) {
        var parts = parts(UserDefaults.standard.string(forKey: storageKey) ?? "")
        guard parts.indices.contains(index) else { return }
        parts[index] = focus?.rawValue ?? ""
        let stored = parts.allSatisfy(\.isEmpty) ? "" : parts.joined(separator: ",")
        UserDefaults.standard.set(stored, forKey: storageKey)
    }

    static func weekdayName(_ index: Int, calendar: Calendar = .current) -> String {
        let start = PlanBuilder.startOfWeek(calendar: calendar)
        let day = calendar.date(byAdding: .day, value: index, to: start) ?? start
        return day.formatted(.dateTime.weekday(.wide))
    }

    private static func parts(_ raw: String) -> [String] {
        let split = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if split.count == 7 { return split }
        return Array(repeating: "", count: 7)
    }
}

/// Shared week so the home list updates as soon as a day is chosen.
@MainActor
final class WeekSplitStore: ObservableObject {
    static let shared = WeekSplitStore()

    @Published private(set) var raw: String

    private init() {
        raw = UserDefaults.standard.string(forKey: WeekSplit.storageKey) ?? ""
    }

    func focus(weekday index: Int) -> TrainingFocus? {
        WeekSplit.focus(weekday: index, in: raw)
    }

    func focus(on date: Date) -> TrainingFocus? {
        focus(weekday: PlanBuilder.mondayIndex(date))
    }

    func set(_ focus: TrainingFocus?, weekday index: Int) {
        WeekSplit.set(focus, weekday: index)
        raw = UserDefaults.standard.string(forKey: WeekSplit.storageKey) ?? ""
        Task { await DayReminder.reschedule() }
    }
}
