import Foundation

enum Goal: String, CaseIterable, Identifiable {
    case strength, fatLoss, mobility, consistency
    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: return String(localized: "Get stronger")
        case .fatLoss: return String(localized: "Lose fat, keep muscle")
        case .mobility: return String(localized: "Move without pain")
        case .consistency: return String(localized: "Build a habit that sticks")
        }
    }
    var subtitle: String {
        switch self {
        case .strength: return String(localized: "Progressive strength with perfect form")
        case .fatLoss: return String(localized: "Shorter rests, more work per minute")
        case .mobility: return String(localized: "Controlled reps, full range of motion")
        case .consistency: return String(localized: "Short sessions you'll actually do")
        }
    }
    var symbol: String {
        switch self {
        case .strength: return "bolt.fill"
        case .fatLoss: return "flame.fill"
        case .mobility: return "figure.flexibility"
        case .consistency: return "calendar"
        }
    }
}

enum TrainingPlace: String, CaseIterable, Identifiable {
    case home, gym, both
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return String(localized: "At home")
        case .gym: return String(localized: "At the gym")
        case .both: return String(localized: "Both")
        }
    }
    var subtitle: String {
        switch self {
        case .home: return String(localized: "No equipment needed")
        case .gym: return String(localized: "Dumbbells and barbells")
        case .both: return String(localized: "Alternate home and gym days")
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .gym: return "dumbbell.fill"
        case .both: return "arrow.left.arrow.right"
        }
    }
}

enum Level: String, CaseIterable, Identifiable {
    case beginner, intermediate, advanced
    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: return String(localized: "Beginner")
        case .intermediate: return String(localized: "Intermediate")
        case .advanced: return String(localized: "Advanced")
        }
    }
    var subtitle: String {
        switch self {
        case .beginner: return String(localized: "New to training or coming back")
        case .intermediate: return String(localized: "Training regularly for 6+ months")
        case .advanced: return String(localized: "Years of consistent lifting")
        }
    }
    var sets: Int { [2, 3, 4][index] }
    var reps: Int { [8, 10, 12][index] }
    var holdSeconds: Int { [20, 30, 45][index] }
    private var index: Int { Level.allCases.firstIndex(of: self) ?? 0 }
}

struct PlannedExercise: Identifiable, Hashable {
    var id = UUID()
    var exerciseID: String
    var sets: Int
    /// Reps per set, or seconds for holds.
    var target: Int
    var restSeconds: Int
    var weightKg: Double?
}

struct ActiveWorkout: Identifiable {
    let id = UUID()
    let title: String
    let plan: [PlannedExercise]
}

struct WorkoutPlan {
    var title: String
    var focus: String
    var items: [PlannedExercise]
    var lockedCount: Int

    var estimatedMinutes: Int {
        guard !items.isEmpty else { return 0 }
        let seconds = items.reduce(0) { $0 + $1.sets * (45 + $1.restSeconds) }
        return max(5, seconds / 60)
    }
}

enum PlanBuilder {
    /// Monday-based index: 0 is Monday, 6 is Sunday.
    static func mondayIndex(_ date: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    static func startOfWeek(containing date: Date = .now, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -mondayIndex(start, calendar: calendar), to: start) ?? start
    }

    static func today(place: TrainingPlace, level: Level, goal: Goal, isPro: Bool, date: Date = .now) -> WorkoutPlan {
        plan(on: date, place: place, level: level, goal: goal, isPro: isPro, split: nil)
    }

    /// The session scheduled for a calendar day. Each weekday has its own exercises.
    static func plan(on date: Date, place: TrainingPlace, level: Level, goal: Goal, isPro: Bool, split: String? = nil) -> WorkoutPlan {
        let raw = split ?? UserDefaults.standard.string(forKey: WeekSplit.storageKey) ?? ""
        let template = template(for: date, place: place, split: raw)
        let rest = restSeconds(goal: goal, level: level)
        guard !template.ids.isEmpty else {
            return WorkoutPlan(title: template.title, focus: template.blurb, items: [], lockedCount: 0)
        }

        let items = template.ids.map { make($0, level: level, rest: rest) }
        let locked = isPro ? 0 : items.filter { !ExerciseLibrary.freeIDs.contains($0.exerciseID) }.count
        return WorkoutPlan(title: template.title, focus: template.blurb, items: items, lockedCount: locked)
    }

    /// Replaces the scheduled exercise list when the user changed that day.
    static func applying(_ ids: [String]?, onto scheduled: WorkoutPlan, level: Level, goal: Goal, isPro: Bool) -> WorkoutPlan {
        guard let ids, !ids.isEmpty else { return scheduled }
        let rest = scheduled.items.first?.restSeconds ?? restSeconds(goal: goal, level: level)
        if isPro {
            let items = ids.map { make($0, level: level, rest: rest) }
            return WorkoutPlan(title: scheduled.title, focus: scheduled.focus, items: items, lockedCount: 0)
        }
        let allowed = ids.filter { ExerciseLibrary.freeIDs.contains($0) }
        let locked = ids.count - allowed.count
        let visibleIDs = allowed.isEmpty ? ["squat"] : allowed
        let items = visibleIDs.map { make($0, level: level, rest: rest) }
        return WorkoutPlan(title: scheduled.title, focus: scheduled.focus, items: items, lockedCount: locked)
    }

    private static func restSeconds(goal: Goal, level: Level) -> Int {
        switch goal {
        case .fatLoss: return 40
        case .strength: return level == .beginner ? 60 : 90
        default: return 60
        }
    }

    private struct DayTemplate {
        let title: String
        let blurb: String
        let ids: [String]
    }

    private static let homeDays: [DayTemplate] = [
        DayTemplate(title: String(localized: "Full Body Strength"), blurb: String(localized: "Squat, push, and a short core finisher."), ids: ["squat", "pushUp", "gluteBridge", "plank"]),
        DayTemplate(title: String(localized: "Lower Body"), blurb: String(localized: "Lunges and squats for the legs."), ids: ["lunge", "squat", "gluteBridge"]),
        DayTemplate(title: String(localized: "Push & Core"), blurb: String(localized: "Push-ups with a brace for your midline."), ids: ["pushUp", "plank", "squat"]),
        DayTemplate(title: String(localized: "Full Body B"), blurb: String(localized: "A second full-body day so Monday isn't the only hard one."), ids: ["lunge", "pushUp", "plank", "gluteBridge"]),
        DayTemplate(title: String(localized: "Legs & Glutes"), blurb: String(localized: "Squat pattern again, then glutes."), ids: ["squat", "lunge", "gluteBridge", "plank"]),
        DayTemplate(title: String(localized: "Conditioning"), blurb: String(localized: "Shorter rest. Keep the reps clean."), ids: ["pushUp", "squat", "lunge", "plank"]),
        DayTemplate(title: String(localized: "Recovery"), blurb: String(localized: "Easy core and glutes. Keep the streak without grinding."), ids: ["plank", "gluteBridge"])
    ]

    private static let gymDays: [DayTemplate] = [
        DayTemplate(title: String(localized: "Squat & Press"), blurb: String(localized: "A heavy lower pattern and an overhead press."), ids: ["squat", "overheadPress", "plank"]),
        DayTemplate(title: String(localized: "Hinge"), blurb: String(localized: "Romanian deadlifts, hip thrusts and lunges."), ids: ["rdl", "hipThrust", "lunge"]),
        DayTemplate(title: String(localized: "Push"), blurb: String(localized: "Bench, then shoulders."), ids: ["bench", "overheadPress", "lateralRaise"]),
        DayTemplate(title: String(localized: "Lower Strength"), blurb: String(localized: "Squat, hinge, then hips."), ids: ["squat", "rdl", "hipThrust"]),
        DayTemplate(title: String(localized: "Shoulders & Arms"), blurb: String(localized: "A row, then raises, curls and a press."), ids: ["row", "lateralRaise", "bicepCurl", "overheadPress"]),
        DayTemplate(title: String(localized: "Gym Full Body"), blurb: String(localized: "Squat, bench and a row."), ids: ["squat", "bench", "row", "plank"]),
        DayTemplate(title: String(localized: "Core"), blurb: String(localized: "A short day. Show up, then rest."), ids: ["plank", "gluteBridge", "pushUp"])
    ]

    private static func template(for date: Date, place: TrainingPlace, split raw: String) -> DayTemplate {
        let index = mondayIndex(date)
        if let focus = WeekSplit.focus(weekday: index, in: raw) {
            return DayTemplate(title: focus.dayName, blurb: focus.detail, ids: focus.exerciseIDs(place: place))
        }
        switch place {
        case .home:
            return homeDays[index]
        case .gym:
            return gymDays[index]
        case .both:
            let gymDay = index == 0 || index == 2 || index == 4
            return (gymDay ? gymDays : homeDays)[index]
        }
    }

    static func chipLabel(on date: Date, place: TrainingPlace, split raw: String) -> String {
        if let focus = WeekSplit.focus(weekday: mondayIndex(date), in: raw) { return focus.shortTitle }
        let index = mondayIndex(date)
        let gym = place == .gym || (place == .both && (index == 0 || index == 2 || index == 4))
        if gym {
            return [String(localized: "Legs"), String(localized: "Legs"), String(localized: "Push"), String(localized: "Legs"), String(localized: "Delts"), String(localized: "Full"), String(localized: "Core")][index]
        }
        return [String(localized: "Full"), String(localized: "Legs"), String(localized: "Push"), String(localized: "Full"), String(localized: "Legs"), String(localized: "Push"), String(localized: "Rest")][index]
    }

    static func make(_ id: String, level: Level, rest: Int) -> PlannedExercise {
        let spec = ExerciseLibrary.spec(id)
        let isGymLift = spec.category == .gym
        let target = spec.kind.isHold ? level.holdSeconds : (isGymLift ? max(6, level.reps - 2) : level.reps)
        return PlannedExercise(exerciseID: id, sets: level.sets, target: target, restSeconds: rest,
                               weightKg: isGymLift ? 0 : nil)
    }
}
