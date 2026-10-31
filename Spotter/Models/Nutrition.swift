import Foundation
import SwiftData

enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return String(localized: "Breakfast")
        case .lunch: return String(localized: "Lunch")
        case .dinner: return String(localized: "Dinner")
        case .snack: return String(localized: "Snack")
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "leaf.fill"
        }
    }
}

struct FoodServing: Identifiable, Hashable {
    let id: String
    let name: String
    let serving: String
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
}

enum FoodCatalog {
    static let all: [FoodServing] = [
        FoodServing(id: "eggs", name: "Eggs", serving: "2 eggs", calories: 140, protein: 12, carbs: 1, fat: 10),
        FoodServing(id: "yogurt", name: "Greek yogurt", serving: "170 g", calories: 100, protein: 17, carbs: 6, fat: 0),
        FoodServing(id: "oats", name: "Oats", serving: "50 g dry", calories: 190, protein: 7, carbs: 32, fat: 4),
        FoodServing(id: "banana", name: "Banana", serving: "1 medium", calories: 105, protein: 1, carbs: 27, fat: 0),
        FoodServing(id: "berries", name: "Berries", serving: "100 g", calories: 50, protein: 1, carbs: 12, fat: 0),
        FoodServing(id: "bread", name: "Whole-wheat bread", serving: "2 slices", calories: 160, protein: 8, carbs: 28, fat: 2),
        FoodServing(id: "peanut", name: "Peanut butter", serving: "1 tbsp", calories: 90, protein: 4, carbs: 3, fat: 8),
        FoodServing(id: "cottage", name: "Cottage cheese", serving: "150 g", calories: 140, protein: 16, carbs: 5, fat: 6),
        FoodServing(id: "chicken", name: "Chicken breast", serving: "150 g", calories: 250, protein: 46, carbs: 0, fat: 5),
        FoodServing(id: "salmon", name: "Salmon", serving: "150 g", calories: 280, protein: 30, carbs: 0, fat: 18),
        FoodServing(id: "beef", name: "Lean beef", serving: "150 g", calories: 280, protein: 38, carbs: 0, fat: 14),
        FoodServing(id: "rice", name: "Cooked rice", serving: "150 g", calories: 195, protein: 4, carbs: 43, fat: 0),
        FoodServing(id: "potato", name: "Sweet potato", serving: "150 g", calories: 130, protein: 2, carbs: 30, fat: 0),
        FoodServing(id: "broccoli", name: "Broccoli", serving: "150 g", calories: 50, protein: 4, carbs: 10, fat: 0),
        FoodServing(id: "salad", name: "Green salad", serving: "1 bowl", calories: 40, protein: 2, carbs: 6, fat: 1),
        FoodServing(id: "apple", name: "Apple", serving: "1 medium", calories: 95, protein: 0, carbs: 25, fat: 0),
        FoodServing(id: "shake", name: "Protein shake", serving: "1 scoop", calories: 120, protein: 24, carbs: 3, fat: 2),
        FoodServing(id: "oil", name: "Olive oil", serving: "1 tbsp", calories: 120, protein: 0, carbs: 0, fat: 14)
    ]

    static func food(_ id: String) -> FoodServing? {
        all.first { $0.id == id }
    }
}

struct PlannedMeal: Identifiable, Hashable {
    var id: String
    let slot: MealSlot
    let foodID: String
    let servings: Double

    @MainActor
    var food: FoodServing? { FoodLookup.serving(for: foodID) }
}

enum MealPlanBuilder {
    static func meals(on date: Date, goal: Goal, focus: TrainingFocus? = nil, calendar: Calendar = .current) -> [PlannedMeal] {
        if let focus, focus != .rest {
            return trainingMeals(goal: goal, focus: focus)
        }
        let index = PlanBuilder.mondayIndex(date, calendar: calendar) % patterns(for: goal).count
        return patterns(for: goal)[index]
    }

    /// Meals that belong with the exercise plan on that day.
    private static func trainingMeals(goal: Goal, focus: TrainingFocus) -> [PlannedMeal] {
        if goal == .fatLoss || goal == .mobility {
            return day([
                (.breakfast, "eggs", 1), (.breakfast, "berries", 1),
                (.lunch, "chicken", 1), (.lunch, "salad", 1),
                (.dinner, "salmon", 1), (.dinner, "broccoli", 1),
                (.snack, "yogurt", 1)
            ])
        }
        switch focus {
        case .push, .chest, .shoulders, .arms:
            return day([
                (.breakfast, "oats", 1), (.breakfast, "banana", 1),
                (.lunch, "chicken", 1), (.lunch, "rice", 1),
                (.dinner, "potato", 1), (.snack, "shake", 1)
            ])
        case .legs:
            return day([
                (.breakfast, "eggs", 1), (.breakfast, "oats", 1),
                (.lunch, "beef", 1), (.lunch, "potato", 1),
                (.dinner, "salmon", 1), (.dinner, "broccoli", 1),
                (.snack, "cottage", 1)
            ])
        case .pull, .back:
            return day([
                (.breakfast, "eggs", 1), (.breakfast, "bread", 1),
                (.lunch, "salmon", 1), (.lunch, "rice", 1),
                (.dinner, "chicken", 1), (.snack, "yogurt", 1)
            ])
        default:
            return day([
                (.breakfast, "oats", 1), (.breakfast, "yogurt", 1),
                (.lunch, "chicken", 1), (.lunch, "rice", 1),
                (.dinner, "beef", 1), (.dinner, "salad", 1),
                (.snack, "apple", 1)
            ])
        }
    }

    private static func patterns(for goal: Goal) -> [[PlannedMeal]] {
        switch goal {
        case .fatLoss:
            return [
                day([(.breakfast, "eggs", 1), (.breakfast, "berries", 1), (.lunch, "chicken", 1), (.lunch, "salad", 1), (.dinner, "salmon", 1), (.dinner, "broccoli", 1), (.snack, "yogurt", 1)]),
                day([(.breakfast, "yogurt", 1), (.breakfast, "berries", 1), (.lunch, "beef", 1), (.lunch, "salad", 1), (.dinner, "chicken", 1), (.dinner, "broccoli", 2), (.snack, "cottage", 1)]),
                day([(.breakfast, "cottage", 1), (.breakfast, "apple", 1), (.lunch, "salmon", 1), (.lunch, "salad", 1), (.dinner, "chicken", 1), (.dinner, "potato", 1), (.snack, "shake", 1)])
            ]
        case .strength:
            return [
                day([(.breakfast, "oats", 1), (.breakfast, "banana", 1), (.lunch, "chicken", 1), (.lunch, "rice", 1), (.dinner, "beef", 1), (.dinner, "potato", 1), (.snack, "shake", 1)]),
                day([(.breakfast, "eggs", 1), (.breakfast, "bread", 1), (.lunch, "salmon", 1), (.lunch, "rice", 1), (.dinner, "chicken", 1), (.dinner, "potato", 1), (.snack, "yogurt", 1)]),
                day([(.breakfast, "oats", 1), (.breakfast, "peanut", 1), (.lunch, "beef", 1), (.lunch, "rice", 2), (.dinner, "salmon", 1), (.dinner, "broccoli", 1), (.snack, "cottage", 1)])
            ]
        case .mobility, .consistency:
            return [
                day([(.breakfast, "oats", 1), (.breakfast, "berries", 1), (.lunch, "chicken", 1), (.lunch, "rice", 1), (.dinner, "salmon", 1), (.dinner, "salad", 1), (.snack, "apple", 1)]),
                day([(.breakfast, "yogurt", 1), (.breakfast, "banana", 1), (.lunch, "beef", 1), (.lunch, "potato", 1), (.dinner, "chicken", 1), (.dinner, "broccoli", 1), (.snack, "bread", 1)]),
                day([(.breakfast, "eggs", 1), (.breakfast, "bread", 1), (.lunch, "salmon", 1), (.lunch, "salad", 1), (.dinner, "chicken", 1), (.dinner, "rice", 1), (.snack, "yogurt", 1)])
            ]
        }
    }

    private static func day(_ items: [(MealSlot, String, Double)]) -> [PlannedMeal] {
        items.map { PlannedMeal(id: "\($0.0.rawValue)-\($0.1)", slot: $0.0, foodID: $0.1, servings: $0.2) }
    }
}

struct MacroTarget: Equatable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
}

enum NutritionTarget {
    static let caloriesKey = "nutrition.calories"
    static let proteinKey = "nutrition.protein"
    static let carbsKey = "nutrition.carbs"
    static let fatKey = "nutrition.fat"
    static let customKey = "nutrition.custom"

    static var isCustom: Bool {
        UserDefaults.standard.bool(forKey: customKey)
    }

    static func suggested(goal: Goal, weightKg: Double?) -> MacroTarget {
        let kg = max(weightKg ?? 75, 40)
        let maintenance = Int((kg * 31).rounded())
        let calories: Int
        switch goal {
        case .fatLoss: calories = max(1400, Int((Double(maintenance) * 0.8).rounded()))
        case .strength: calories = maintenance + 250
        default: calories = maintenance
        }
        let proteinPerKg: Double = goal == .fatLoss ? 2.0 : goal == .strength ? 1.8 : 1.6
        let protein = Int((kg * proteinPerKg).rounded())
        let fat = max(35, Int((Double(calories) * 0.28 / 9).rounded()))
        let carbs = max(0, (calories - protein * 4 - fat * 9) / 4)
        return MacroTarget(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    static func current(goal: Goal, weightKg: Double?) -> MacroTarget {
        let defaults = UserDefaults.standard
        let saved = defaults.integer(forKey: caloriesKey)
        guard defaults.bool(forKey: customKey), saved > 0 else {
            return suggested(goal: goal, weightKg: weightKg)
        }
        return MacroTarget(
            calories: saved,
            protein: defaults.integer(forKey: proteinKey),
            carbs: defaults.integer(forKey: carbsKey),
            fat: defaults.integer(forKey: fatKey)
        )
    }

    static func save(_ target: MacroTarget) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: customKey)
        defaults.set(target.calories, forKey: caloriesKey)
        defaults.set(target.protein, forKey: proteinKey)
        defaults.set(target.carbs, forKey: carbsKey)
        defaults.set(target.fat, forKey: fatKey)
    }

    static func reset() {
        UserDefaults.standard.set(false, forKey: customKey)
    }
}

@Model
final class MealEntry {
    var id: UUID
    var date: Date
    var slotRaw: String
    var name: String
    var servings: Double
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double

    var slot: MealSlot { MealSlot(rawValue: slotRaw) ?? .snack }

    init(date: Date, slot: MealSlot, name: String, servings: Double, calories: Int, protein: Double, carbs: Double, fat: Double) {
        self.id = UUID()
        self.date = date
        self.slotRaw = slot.rawValue
        self.name = name
        self.servings = servings
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    static func logged(food: FoodServing, servings: Double, slot: MealSlot, on date: Date) -> MealEntry {
        MealEntry(
            date: date,
            slot: slot,
            name: food.name,
            servings: servings,
            calories: Int((Double(food.calories) * servings).rounded()),
            protein: food.protein * servings,
            carbs: food.carbs * servings,
            fat: food.fat * servings
        )
    }
}
