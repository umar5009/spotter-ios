import SwiftUI

struct CustomMealPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MealPlanStore.shared
    let goal: Goal
    @State private var plan: SavedMealPlan
    @State private var showAdd = false

    init(plan: SavedMealPlan?, goal: Goal) {
        self.goal = goal
        _plan = State(initialValue: plan ?? SavedMealPlan(
            title: String(localized: "My meal plan"),
            note: String(localized: "Foods you added."),
            items: [],
            fromCoach: false
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Plan name", text: $plan.title)
                }
                if plan.items.isEmpty {
                    Section {
                        Text("Add a product you eat. It can be anything, even if it is not in Spotter's list.")
                            .foregroundStyle(Theme.textSecondary)
                        Button("Start from the suggestion") { fillSuggestion() }
                    }
                }
                ForEach(MealSlot.allCases) { slot in
                    let rows = plan.items.filter { $0.slot == slot }
                    if !rows.isEmpty {
                        Section(slot.title) {
                            ForEach(rows) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(FoodLookup.serving(for: item.foodID)?.name ?? String(localized: "Food"))
                                        if let food = FoodLookup.serving(for: item.foodID) {
                                            Text(food.calories == 0
                                                 ? String(localized: "Calories not set")
                                                 : "\(food.calories) kcal · \(food.serving)")
                                                .font(.caption)
                                                .foregroundStyle(Theme.textTertiary)
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        plan.items.removeAll { $0.id == item.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add a product", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Your foods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(plan.items.isEmpty || plan.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showAdd) {
                AddProductSheet { item, food in
                    if let food { store.addFood(food) }
                    plan.items.append(item)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func fillSuggestion() {
        let meals = MealPlanBuilder.meals(on: .now, goal: goal)
        plan.items = meals.map {
            SavedMealItem(id: UUID(), slotRaw: $0.slot.rawValue, foodID: $0.foodID, servings: $0.servings)
        }
        plan.note = String(localized: "Started from the suggestion. Add or remove products.")
        plan.fromCoach = false
    }

    private func save() {
        plan.title = plan.title.trimmingCharacters(in: .whitespaces)
        plan.fromCoach = false
        if plan.note.isEmpty {
            plan.note = String(localized: "Foods you added.")
        }
        store.save(plan: plan)
        SpotterAnalytics.click("save_custom_meal_plan", screen: "meals")
        dismiss()
    }
}

struct AddProductSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MealPlanStore.shared
    var onAdd: (SavedMealItem, CustomFood?) -> Void

    @State private var slot: MealSlot = .breakfast
    @State private var name = ""
    @State private var serving = "1 serving"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var servings = 1.0
    @State private var query = ""

    private var catalog: [FoodServing] {
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
                Section("Your product") {
                    TextField("Name", text: $name)
                    TextField("Serving", text: $serving)
                    TextField("Calories", text: $calories).keyboardType(.numberPad)
                    TextField("Protein g", text: $protein).keyboardType(.decimalPad)
                    TextField("Carbs g", text: $carbs).keyboardType(.decimalPad)
                    TextField("Fat g", text: $fat).keyboardType(.decimalPad)
                    Button("Add this product") { addCustom() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !store.foods.isEmpty {
                    Section("Saved products") {
                        ForEach(store.foods) { food in
                            Button(food.name) { add(foodID: food.id, custom: nil) }
                        }
                    }
                }
                Section("Spotter foods") {
                    TextField("Search", text: $query)
                    ForEach(catalog) { food in
                        Button {
                            add(foodID: food.id, custom: nil)
                        } label: {
                            HStack {
                                Text(food.name).foregroundStyle(.white)
                                Spacer()
                                Text("\(food.calories) kcal")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add a product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func addCustom() {
        let food = CustomFood(
            id: "custom:\(UUID().uuidString)",
            name: name.trimmingCharacters(in: .whitespaces),
            serving: serving.trimmingCharacters(in: .whitespaces).isEmpty ? "1 serving" : serving,
            calories: Int(calories) ?? 0,
            protein: Measure.number(protein) ?? 0,
            carbs: Measure.number(carbs) ?? 0,
            fat: Measure.number(fat) ?? 0
        )
        add(foodID: food.id, custom: food)
    }

    private func add(foodID: String, custom: CustomFood?) {
        let item = SavedMealItem(id: UUID(), slotRaw: slot.rawValue, foodID: foodID, servings: servings)
        onAdd(item, custom)
        Haptics.success()
        dismiss()
    }
}
