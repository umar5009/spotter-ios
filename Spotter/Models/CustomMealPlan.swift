import Foundation

struct CustomFood: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var serving: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double

    var asServing: FoodServing {
        FoodServing(id: id, name: name, serving: serving, calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
}

struct SavedMealItem: Codable, Identifiable, Equatable {
    var id: UUID
    var slotRaw: String
    var foodID: String
    var servings: Double

    var slot: MealSlot {
        get { MealSlot(rawValue: slotRaw) ?? .snack }
        set { slotRaw = newValue.rawValue }
    }
}

struct SavedMealPlan: Codable, Equatable {
    var title: String
    var note: String
    var items: [SavedMealItem]
    var fromCoach: Bool
}

enum FoodLookup {
    @MainActor
    static func serving(for id: String) -> FoodServing? {
        if id.hasPrefix("custom:") {
            return MealPlanStore.shared.foods.first { $0.id == id }?.asServing
        }
        return FoodCatalog.food(id)
    }
}

@MainActor
final class MealPlanStore: ObservableObject {
    static let shared = MealPlanStore()

    @Published private(set) var plan: SavedMealPlan?
    @Published private(set) var foods: [CustomFood] = []

    private let planKey = "nutrition.customPlan"
    private let foodsKey = "nutrition.customFoods"

    private init() {
        if let data = UserDefaults.standard.data(forKey: foodsKey),
           let saved = try? JSONDecoder().decode([CustomFood].self, from: data) {
            foods = saved
        }
        if let data = UserDefaults.standard.data(forKey: planKey),
           let saved = try? JSONDecoder().decode(SavedMealPlan.self, from: data) {
            plan = saved
        }
    }

    func meals() -> [PlannedMeal] {
        guard let plan else { return [] }
        return plan.items.map {
            PlannedMeal(id: $0.id.uuidString, slot: $0.slot, foodID: $0.foodID, servings: $0.servings)
        }
    }

    func save(plan: SavedMealPlan, foods extra: [CustomFood] = []) {
        for food in extra where !foods.contains(where: { $0.id == food.id }) {
            foods.append(food)
        }
        self.plan = plan
        persist()
    }

    func addFood(_ food: CustomFood) {
        if let index = foods.firstIndex(where: { $0.id == food.id }) {
            foods[index] = food
        } else {
            foods.append(food)
        }
        persistFoods()
    }

    func clear() {
        plan = nil
        UserDefaults.standard.removeObject(forKey: planKey)
    }

    private func persist() {
        persistFoods()
        if let plan, let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: planKey)
        }
    }

    private func persistFoods() {
        if let data = try? JSONEncoder().encode(foods) {
            UserDefaults.standard.set(data, forKey: foodsKey)
        }
    }
}

enum CoachStep: Equatable {
    case age
    case weight
    case focus
    case days
    case foods
    case avoid
}

struct CoachPrompt: Equatable {
    var step: CoachStep
    var text: String
    var chips: [String]
}

struct CoachAnswers {
    var age: Int?
    var weightKg: Double?
    var goal: Goal?
    var days: Int?
    var foods: [String] = []
    var avoid: [String] = []
    var askedWeight = false
}

struct CoachBuiltPlan {
    var message: String
    var age: Int?
    var weightKg: Double?
    var goal: Goal?
    var days: [(Date, [String])] = []
    var mealPlan: SavedMealPlan?
    var foods: [CustomFood] = []
}

@MainActor
enum CoachPlanner {
    static func prompts(age: Int, weightKg: Double?, unit: Measure.Weight) -> [CoachPrompt] {
        var steps: [CoachPrompt] = []
        if age <= 0 {
            steps.append(CoachPrompt(step: .age, text: String(localized: "How old are you?"), chips: []))
        }
        if weightKg == nil {
            steps.append(CoachPrompt(
                step: .weight,
                text: String(localized: "What do you weigh, in \(unit.symbol)?"),
                chips: []
            ))
        }
        steps.append(CoachPrompt(
            step: .focus,
            text: String(localized: "What do you want from training right now?"),
            chips: [
                String(localized: "Get stronger"),
                String(localized: "Lose fat"),
                String(localized: "Easier joints"),
                String(localized: "Short sessions")
            ]
        ))
        steps.append(CoachPrompt(
            step: .days,
            text: String(localized: "How many days can you train this week?"),
            chips: ["2", "3", "4", "5"]
        ))
        steps.append(CoachPrompt(
            step: .foods,
            text: String(localized: "Which foods do you already have? Separate them with commas. Say anything if you want me to pick."),
            chips: [String(localized: "You pick")]
        ))
        steps.append(CoachPrompt(
            step: .avoid,
            text: String(localized: "Anything you don't eat? Say none if the list above is fine."),
            chips: [String(localized: "None")]
        ))
        return steps
    }

    static func opener(age: Int, weightKg: Double?, unit: Measure.Weight) -> String {
        var known = ""
        if age > 0 {
            known += " " + String(localized: "I have your age as \(age).")
        }
        if let weightKg {
            let shown = Measure.format(unit.fromKilograms(weightKg))
            known += " " + String(localized: "Your latest weigh-in is \(shown) \(unit.symbol).")
        }
        return String(localized: "I'll ask a few questions, then put exercises on Today and a meal plan on Meals.\(known) This is a training aid, not medical advice.")
    }

    static func accept(_ text: String, step: CoachStep, unit: Measure.Weight, into answers: inout CoachAnswers) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch step {
        case .age:
            guard let age = Int(trimmed.filter(\.isNumber)), (13...90).contains(age) else {
                if let age = Int(trimmed.filter(\.isNumber)), age > 0, age < 13 {
                    return String(localized: "Spotter is for people 13 and older.")
                }
                return String(localized: "Enter an age from 13 to 90.")
            }
            answers.age = age
        case .weight:
            guard let value = Measure.number(trimmed), unit.accepts(value) else {
                return String(localized: "Enter a weight between \(unit.rangeDescription).")
            }
            answers.weightKg = unit.toKilograms(value)
            answers.askedWeight = true
        case .focus:
            guard let goal = goal(from: trimmed) else {
                return String(localized: "Choose Get stronger, Lose fat, Easier joints, or Short sessions.")
            }
            answers.goal = goal
        case .days:
            guard let days = Int(trimmed), (2...5).contains(days) else {
                return String(localized: "Choose 2, 3, 4, or 5 days.")
            }
            answers.days = days
        case .foods:
            let picked = names(in: trimmed)
            if picked.isEmpty, !isSkip(trimmed) {
                return String(localized: "Name a few foods, or say you pick.")
            }
            answers.foods = isSkip(trimmed) ? [] : picked
        case .avoid:
            answers.avoid = isNone(trimmed) ? [] : names(in: trimmed)
        }
        return nil
    }

    static func build(answers: CoachAnswers, place: TrainingPlace, level: Level, isPro: Bool, heightCm: Double, unit: Measure.Weight, now: Date = .now) -> CoachBuiltPlan {
        guard let age = answers.age, age >= 13 else {
            return CoachBuiltPlan(message: String(localized: "I need an age of 13 or older before I can build a plan."))
        }
        let requested = answers.goal ?? .strength
        let goal: Goal = age < 18 && requested == .fatLoss ? .consistency : requested
        let weight = answers.weightKg
        let gentle = age >= 60 || goal == .mobility || highBodyMass(weightKg: weight, heightCm: heightCm)
        let ids = exercises(place: place == .both ? .home : place, goal: goal, gentle: gentle, isPro: isPro)
        let days = answers.days ?? 3
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let schedule: [(Date, [String])] = (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return (date, rotate(ids, by: offset))
        }
        let meal = mealPlan(foods: answers.foods, avoid: answers.avoid, goal: age < 18 ? .consistency : goal)
        let names = ids.map { ExerciseLibrary.spec($0).name }
        var lines: [String] = []
        lines.append(String(localized: "Today: \(names.joined(separator: ", ")). I set \(days) training days, starting today."))
        if age < 18 && requested == .fatLoss {
            lines.append(String(localized: "Under 18, the plan stays at maintenance instead of a fat-loss deficit."))
        }
        if gentle && goal != .mobility {
            lines.append(String(localized: "I kept the exercises to squats, hinges, and pushes you can do with control."))
        }
        lines.append(meal.plan.note)
        if meal.plan.items.isEmpty {
            lines.append(String(localized: "I couldn't place those foods. Add them yourself on Meals."))
        } else {
            let preview = meal.plan.items.prefix(6).map { item -> String in
                let name = meal.foods.first { $0.id == item.foodID }?.name
                    ?? FoodCatalog.food(item.foodID)?.name
                    ?? item.foodID
                return "\(item.slot.title): \(name)"
            }
            lines.append(preview.joined(separator: "\n"))
        }
        let target = NutritionTarget.suggested(goal: goal, weightKg: weight)
        lines.append(String(localized: "Calorie target \(target.calories) kcal."))
        lines.append(String(localized: "Use this exercise and meal plan, or pick your own?"))
        return CoachBuiltPlan(
            message: lines.joined(separator: "\n\n"),
            age: age,
            weightKg: answers.askedWeight ? weight : nil,
            goal: goal,
            days: schedule,
            mealPlan: meal.plan,
            foods: meal.foods
        )
    }

    static func apply(_ built: CoachBuiltPlan) {
        applyExercises(built.days)
        applyMeals(built)
    }

    static func applyExercises(_ days: [(Date, [String])], focus: TrainingFocus = .fullBody) {
        for (date, ids) in days where !ids.isEmpty {
            WeekSplitStore.shared.set(focus, weekday: PlanBuilder.mondayIndex(date))
            DayPlanEdit.save(ids, on: date)
        }
    }

    static func applyMeals(_ built: CoachBuiltPlan) {
        guard let plan = built.mealPlan else { return }
        if built.foods.isEmpty {
            MealPlanStore.shared.clear()
            return
        }
        MealPlanStore.shared.save(plan: plan, foods: built.foods)
    }

    static func exerciseChoices(place: TrainingPlace, isPro: Bool) -> [(title: String, focus: TrainingFocus, ids: [String]?)] {
        let gym = place == .gym
        let options: [(String, TrainingFocus, [String]?)] = [
            (String(localized: "Full body"), .fullBody, gym ? ["squat", "bench", "row", "plank"] : ["squat", "pushUp", "lunge", "plank"]),
            (String(localized: "Push"), .push, gym ? ["bench", "overheadPress", "pushUp", "plank"] : ["pushUp", "squat", "plank", "gluteBridge"]),
            (String(localized: "Lower body"), .legs, gym ? ["squat", "rdl", "lunge", "hipThrust"] : ["squat", "lunge", "gluteBridge", "plank"]),
            (String(localized: "Keep my workout"), .fullBody, nil)
        ]
        return options.map { title, focus, ids in
            guard let ids else { return (title, focus, nil) }
            let allowed = isPro ? ids : ids.filter { ExerciseLibrary.freeIDs.contains($0) }
            return (title, focus, allowed.isEmpty ? ["squat", "pushUp", "plank"] : allowed)
        }
    }

    static func schedule(_ ids: [String], on dates: [Date]) -> [(Date, [String])] {
        dates.enumerated().map { offset, date in
            let shift = ids.isEmpty ? 0 : offset % ids.count
            let rotated = Array(ids[shift...] + ids[..<shift])
            return (date, rotated)
        }
    }

    private static func exercises(place: TrainingPlace, goal: Goal, gentle: Bool, isPro: Bool) -> [String] {
        let ids: [String]
        if gentle {
            ids = place == .gym
                ? ["gluteBridge", "row", "hipThrust", "plank"]
                : ["squat", "gluteBridge", "lunge", "plank"]
        } else {
            switch (place, goal) {
            case (.gym, .strength):
                ids = ["squat", "bench", "row", "rdl"]
            case (.gym, .fatLoss):
                ids = ["squat", "row", "overheadPress", "plank"]
            case (_, .mobility):
                ids = isPro
                    ? ["gluteBridge", "birdDog", "hipFlexorStretch", "plank"]
                    : ["gluteBridge", "lunge", "plank", "squat"]
            case (_, .consistency):
                ids = ["squat", "pushUp", "gluteBridge", "plank"]
            case (.gym, _):
                ids = ["squat", "bench", "row", "plank"]
            case (_, .strength):
                ids = ["squat", "pushUp", "lunge", "gluteBridge"]
            default:
                ids = ["squat", "pushUp", "lunge", "plank"]
            }
        }
        let allowed = isPro ? ids : ids.filter { ExerciseLibrary.freeIDs.contains($0) }
        return allowed.isEmpty ? ["squat", "pushUp", "plank"] : allowed
    }

    private static func mealPlan(foods named: [String], avoid: [String], goal: Goal) -> (plan: SavedMealPlan, foods: [CustomFood]) {
        let slots = MealSlot.allCases
        var custom: [CustomFood] = []
        var items: [SavedMealItem] = []
        for (index, name) in named.enumerated() {
            if blocked(name, avoid: avoid) { continue }
            let food = estimate(name)
            custom.append(food)
            items.append(SavedMealItem(
                id: UUID(),
                slotRaw: slots[index % slots.count].rawValue,
                foodID: food.id,
                servings: 1
            ))
        }
        if items.count < 4 {
            let filler = MealPlanBuilder.meals(on: .now, goal: goal)
            for meal in filler where items.count < 6 {
                guard let food = meal.food, !blocked(food.name, avoid: avoid) else { continue }
                if items.contains(where: { $0.foodID == meal.foodID }) { continue }
                items.append(SavedMealItem(id: UUID(), slotRaw: meal.slot.rawValue, foodID: meal.foodID, servings: meal.servings))
            }
        }
        let unknown = custom.filter { $0.calories == 0 }.map(\.name)
        var note = named.isEmpty
            ? String(localized: "A starter meal plan for your goal. Add the foods you actually buy.")
            : String(localized: "Built from the foods you named. Portions are a starting point.")
        if !unknown.isEmpty {
            note += " " + String(localized: "Add calories for \(unknown.joined(separator: ", ")).")
        }
        let plan = SavedMealPlan(title: String(localized: "My meal plan"), note: note, items: items, fromCoach: true)
        return (plan, custom)
    }

    private static func estimate(_ name: String) -> CustomFood {
        let lower = name.lowercased()
        let aliases: [(String, String)] = [
            ("egg", "eggs"), ("yogurt", "yogurt"), ("oat", "oats"), ("banana", "banana"),
            ("berr", "berries"), ("bread", "bread"), ("peanut", "peanut"), ("cottage", "cottage"),
            ("chicken", "chicken"), ("salmon", "salmon"), ("tuna", "salmon"), ("beef", "beef"),
            ("steak", "beef"), ("rice", "rice"), ("potato", "potato"), ("broccoli", "broccoli"),
            ("salad", "salad"), ("apple", "apple"), ("shake", "shake"), ("protein", "shake"),
            ("olive", "oil"), ("fish", "salmon")
        ]
        if let match = aliases.first(where: { lower.contains($0.0) }), let known = FoodCatalog.food(match.1) {
            return CustomFood(
                id: "custom:\(UUID().uuidString)",
                name: name,
                serving: known.serving,
                calories: known.calories,
                protein: known.protein,
                carbs: known.carbs,
                fat: known.fat
            )
        }
        return CustomFood(id: "custom:\(UUID().uuidString)", name: name, serving: String(localized: "1 serving"), calories: 0, protein: 0, carbs: 0, fat: 0)
    }

    private static func blocked(_ name: String, avoid: [String]) -> Bool {
        let lower = name.lowercased()
        return avoid.contains { token in
            token.count > 2 && lower.contains(token.lowercased())
        }
    }

    private static func highBodyMass(weightKg: Double?, heightCm: Double) -> Bool {
        guard let weightKg, let bmi = BMI.calculate(weightKg: weightKg, heightCm: heightCm) else { return false }
        return bmi.value >= 30
    }

    private static func rotate(_ ids: [String], by offset: Int) -> [String] {
        guard !ids.isEmpty else { return ids }
        let shift = offset % ids.count
        return Array(ids[shift...] + ids[..<shift])
    }

    private static func goal(from text: String) -> Goal? {
        let lower = text.lowercased()
        if lower.contains("fat") || lower.contains("lean") { return .fatLoss }
        if lower.contains("joint") || lower.contains("easy") || lower.contains("pain") { return .mobility }
        if lower.contains("short") || lower.contains("habit") { return .consistency }
        if lower.contains("strong") { return .strength }
        return nil
    }

    private static func names(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isSkip($0) && !isNone($0) }
    }

    private static func isSkip(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["you pick", "anything", "whatever", "skip", "idk", "you choose"].contains(lower)
    }

    private static func isNone(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["none", "no", "nothing", "nope"].contains(lower)
    }
}
