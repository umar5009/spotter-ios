import SwiftData
import SwiftUI

struct NutritionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @AppStorage("goal") private var goalRaw = Goal.strength.rawValue
    @ObservedObject private var mealPlans = MealPlanStore.shared
    @ObservedObject private var weekSplit = WeekSplitStore.shared
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var showAdd = false
    @State private var addSlot: MealSlot = .breakfast
    @State private var showTargets = false
    @State private var showPlanEditor = false

    private var goal: Goal { Goal(rawValue: goalRaw) ?? .strength }
    private var target: MacroTarget {
        NutritionTarget.current(goal: goal, weightKg: weights.last?.weightKg)
    }
    private var dayMeals: [MealEntry] {
        meals.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
    }
    private var eatenCalories: Int { dayMeals.reduce(0) { $0 + $1.calories } }
    private var eatenProtein: Double { dayMeals.reduce(0) { $0 + $1.protein } }
    private var eatenCarbs: Double { dayMeals.reduce(0) { $0 + $1.carbs } }
    private var eatenFat: Double { dayMeals.reduce(0) { $0 + $1.fat } }
    private var dayPlanName: String {
        weekSplit.focus(on: selectedDay)?.dayName ?? goal.title
    }
    private var namedPlan: Bool {
        guard let saved = mealPlans.plan else { return false }
        if saved.items.contains(where: { $0.foodID.hasPrefix("custom:") }) { return true }
        return !saved.fromCoach && !saved.items.isEmpty
    }
    private var plan: [PlannedMeal] {
        if namedPlan { return mealPlans.meals() }
        return MealPlanBuilder.meals(on: selectedDay, goal: goal, focus: weekSplit.focus(on: selectedDay))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekStrip
                    calorieCard
                    macroCard
                    loggedCard
                    planCard
                    weekSummary
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Targets") {
                        SpotterAnalytics.click("open_nutrition_targets", screen: "meals")
                        showTargets = true
                    }
                    .font(.subheadline.weight(.bold))
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFoodSheet(day: selectedDay, slot: addSlot)
            }
            .sheet(isPresented: $showTargets) {
                NavigationStack {
                    NutritionTargetsView()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showPlanEditor) {
                CustomMealPlanEditor(plan: mealPlans.plan, goal: goal)
            }
        }
    }

    private var weekDates: [Date] {
        let start = PlanBuilder.startOfWeek(containing: selectedDay)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekStrip: some View {
        HStack(spacing: 8) {
            ForEach(weekDates, id: \.self) { day in
                let selected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                Button {
                    selectedDay = Calendar.current.startOfDay(for: day)
                } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.bold))
                        Text(day.formatted(.dateTime.day()))
                            .font(.display(15, weight: .bold))
                    }
                    .foregroundStyle(selected ? Color.black : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selected ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private var calorieCard: some View {
        let over = eatenCalories > target.calories
        let left = abs(target.calories - eatenCalories)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).eyebrow()
                HStack(alignment: .firstTextBaseline) {
                    Text("\(left)")
                        .font(.display(40, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(over ? Theme.bad : .white)
                    Text(over ? String(localized: "over") : String(localized: "left"))
                        .font(.display(18, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(eatenCalories) / \(target.calories)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
                macroBar(eaten: Double(eatenCalories), target: Double(target.calories), color: over ? Theme.bad : Theme.accent)
            }
        }
    }

    private var macroCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Macros").eyebrow()
                macroRow("Protein", eaten: eatenProtein, target: Double(target.protein), color: Theme.accent)
                macroRow("Carbs", eaten: eatenCarbs, target: Double(target.carbs), color: Theme.violet)
                macroRow("Fat", eaten: eatenFat, target: Double(target.fat), color: Theme.warn)
            }
        }
    }

    private func macroRow(_ title: LocalizedStringKey, eaten: Double, target: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Text("\(Int(eaten.rounded())) / \(Int(target.rounded())) g")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
            macroBar(eaten: eaten, target: target, color: color)
        }
    }

    private func macroBar(eaten: Double, target: Double, color: Color) -> some View {
        GeometryReader { geo in
            let width = target > 0 ? min(1, eaten / target) * geo.size.width : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(color).frame(width: width)
            }
        }
        .frame(height: 8)
    }

    private var loggedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Logged").eyebrow()
                    Spacer()
                    Button {
                        addSlot = .breakfast
                        showAdd = true
                    } label: {
                        Label("Add food", systemImage: "plus")
                            .font(.subheadline.weight(.bold))
                    }
                }
                if dayMeals.isEmpty {
                    Text("Nothing logged for this day. Add a food, or log a meal from the plan below.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(MealSlot.allCases) { slot in
                        let rows = dayMeals.filter { $0.slot == slot }
                        if !rows.isEmpty {
                            slotBlock(slot, rows: rows)
                        }
                    }
                }
            }
        }
    }

    private func slotBlock(_ slot: MealSlot, rows: [MealEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(slot.title, systemImage: slot.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
            ForEach(rows) { meal in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meal.name).font(.display(16, weight: .semibold)).foregroundStyle(.white)
                        Text("\(Measure.format(meal.servings)) × · \(meal.calories) kcal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Button {
                        modelContext.delete(meal)
                        Haptics.tap()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var planCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(namedPlan ? (mealPlans.plan?.title ?? String(localized: "Meal plan")) : String(localized: "Meal plan")).eyebrow(Theme.accent)
                    Spacer()
                    Button(namedPlan ? "Edit" : "Your foods") {
                        showPlanEditor = true
                    }
                    .font(.subheadline.weight(.bold))
                }
                Text(namedPlan
                     ? (mealPlans.plan?.note ?? String(localized: "Foods you added."))
                     : String(localized: "\(selectedDay.formatted(.dateTime.weekday(.wide))) meals for \(dayPlanName)."))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                if namedPlan {
                    Button("Use the suggested plan") {
                        mealPlans.clear()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
                ForEach(plan) { meal in
                    if let food = meal.food {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.slot.title).font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                                Text(food.name).font(.display(16, weight: .semibold)).foregroundStyle(.white)
                                Text("\(Measure.format(meal.servings)) × \(food.serving) · \(Int((Double(food.calories) * meal.servings).rounded())) kcal")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Button("Log") {
                                log(food, servings: meal.servings, slot: meal.slot)
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.accent, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private var weekSummary: some View {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .now
        let recent = meals.filter { $0.date >= start }
        let days = Set(recent.map { calendar.startOfDay(for: $0.date) }).count
        let average = days == 0 ? 0 : recent.reduce(0) { $0 + $1.calories } / days
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Last 7 days").eyebrow()
                Text(days == 0 ? String(localized: "Log a meal to see your average.") : String(localized: "\(average) kcal a day across \(days) logged days."))
                    .font(.display(16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func log(_ food: FoodServing, servings: Double, slot: MealSlot) {
        let entry = MealEntry.logged(food: food, servings: servings, slot: slot, on: selectedDay)
        modelContext.insert(entry)
        Haptics.success()
        SpotterAnalytics.log("meal_log", ["slot": slot.rawValue, "food": food.id])
    }
}

struct NutritionTargetsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @AppStorage("goal") private var goalRaw = Goal.strength.rawValue
    @State private var calories = 2000
    @State private var protein = 150
    @State private var carbs = 200
    @State private var fat = 60

    private var goal: Goal { Goal(rawValue: goalRaw) ?? .strength }

    var body: some View {
        List {
            Section {
                stepper("Calories", value: $calories, range: 1200...4500, step: 50, suffix: "kcal")
                stepper("Protein", value: $protein, range: 40...300, step: 5, suffix: "g")
                stepper("Carbs", value: $carbs, range: 0...500, step: 5, suffix: "g")
                stepper("Fat", value: $fat, range: 20...200, step: 5, suffix: "g")
            } footer: {
                Text("Suggested from your goal and latest weigh-in. Saving here keeps your numbers until you reset.")
            }
            Section {
                Button("Use the suggested target") {
                    NutritionTarget.reset()
                    load()
                    SpotterAnalytics.click("reset_nutrition_target", screen: "meals")
                }
            }
        }
        .navigationTitle("Targets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    NutritionTarget.save(MacroTarget(calories: calories, protein: protein, carbs: carbs, fat: fat))
                    SpotterAnalytics.click("save_nutrition_target", screen: "meals")
                    dismiss()
                }
                .fontWeight(.bold)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let current = NutritionTarget.current(goal: goal, weightKg: weights.last?.weightKg)
        calories = current.calories
        protein = current.protein
        carbs = current.carbs
        fat = current.fat
    }

    private func stepper(_ title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>, step: Int, suffix: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) \(suffix)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

struct AddFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let day: Date
    @State var slot: MealSlot
    @State private var query = ""
    @State private var servings = 1.0
    @State private var customName = ""
    @State private var customCalories = ""
    @State private var customProtein = ""
    @State private var customCarbs = ""
    @State private var customFat = ""

    private var foods: [FoodServing] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return FoodCatalog.all }
        return FoodCatalog.all.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Meal", selection: $slot) {
                        ForEach(MealSlot.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper(value: $servings, in: 0.5...6, step: 0.5) {
                        Text("Servings \(Measure.format(servings))")
                    }
                }
                Section("Foods") {
                    TextField("Search", text: $query)
                    ForEach(foods) { food in
                        Button {
                            save(food)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name).foregroundStyle(.white)
                                    Text(food.serving).font(.caption).foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                Text("\(food.calories) kcal")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                Section("Custom food") {
                    TextField("Name", text: $customName)
                    TextField("Calories", text: $customCalories).keyboardType(.numberPad)
                    TextField("Protein g", text: $customProtein).keyboardType(.decimalPad)
                    TextField("Carbs g", text: $customCarbs).keyboardType(.decimalPad)
                    TextField("Fat g", text: $customFat).keyboardType(.decimalPad)
                    Button("Log custom food") { saveCustom() }
                        .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save(_ food: FoodServing) {
        modelContext.insert(MealEntry.logged(food: food, servings: servings, slot: slot, on: day))
        Haptics.success()
        SpotterAnalytics.log("meal_log", ["slot": slot.rawValue, "food": food.id])
        dismiss()
    }

    private func saveCustom() {
        let name = customName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let food = FoodServing(
            id: "custom",
            name: name,
            serving: "1 serving",
            calories: Int(customCalories) ?? 0,
            protein: Measure.number(customProtein) ?? 0,
            carbs: Measure.number(customCarbs) ?? 0,
            fat: Measure.number(customFat) ?? 0
        )
        save(food)
    }
}

struct NutritionWeekCard: View {
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @AppStorage("goal") private var goalRaw = Goal.strength.rawValue
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .now
        let recent = meals.filter { $0.date >= start }
        if recent.isEmpty {
            EmptyView()
        } else {
            let days = Set(recent.map { calendar.startOfDay(for: $0.date) }).count
            let average = recent.reduce(0) { $0 + $1.calories } / max(days, 1)
            let protein = Int(recent.reduce(0) { $0 + $1.protein } / Double(max(days, 1)))
            let target = NutritionTarget.current(goal: Goal(rawValue: goalRaw) ?? .strength, weightKg: weights.last?.weightKg)
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meals").eyebrow()
                    Text("\(average) kcal").font(.display(28, weight: .heavy)).foregroundStyle(.white)
                    Text("Daily average this week · \(protein) g protein · target \(target.calories) kcal")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
