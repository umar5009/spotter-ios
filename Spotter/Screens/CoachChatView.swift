import SwiftData
import SwiftUI

struct CoachChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: StoreManager
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @AppStorage("goal") private var goalRaw = Goal.strength.rawValue
    @AppStorage("place") private var placeRaw = TrainingPlace.home.rawValue
    @AppStorage("level") private var levelRaw = Level.beginner.rawValue
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue
    @AppStorage("heightCm") private var heightCm = 0.0
    @AppStorage("profile.age") private var age = 0

    @State private var messages: [CoachMessage] = []
    @State private var prompts: [CoachPrompt] = []
    @State private var stepIndex = 0
    @State private var answers = CoachAnswers()
    @State private var draft = ""
    @State private var started = false
    @State private var pending: CoachBuiltPlan?
    @State private var choice: CoachChoice = .questions
    @State private var showMealEditor = false

    private var unit: Measure.Weight { Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms }
    private var currentPrompt: CoachPrompt? {
        prompts.indices.contains(stepIndex) ? prompts[stepIndex] : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { message in
                                bubble(message)
                                    .id(message.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                inputBar
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear(perform: start)
            .sheet(isPresented: $showMealEditor, onDismiss: mealEditorClosed) {
                CustomMealPlanEditor(plan: nil, goal: pending?.goal ?? Goal(rawValue: goalRaw) ?? .strength)
            }
        }
        .presentationDetents([.large])
    }

    private func bubble(_ message: CoachMessage) -> some View {
        HStack {
            if message.fromCoach {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: 480, alignment: .leading)
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: 480, alignment: .trailing)
            }
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch choice {
            case .questions:
                if let chips = currentPrompt?.chips, !chips.isEmpty {
                    chipRow(chips) { submit($0) }
                }
                HStack(spacing: 8) {
                    TextField("Answer", text: $draft)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                    Button {
                        submit(draft)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(Theme.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .offer:
                VStack(spacing: 8) {
                    Button("Use this plan") { useSuggested() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Choose my own") { startCustom() }
                        .font(.display(17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            case .exercises:
                chipRow(CoachPlanner.exerciseChoices(place: TrainingPlace(rawValue: placeRaw) ?? .home, isPro: store.isPro).map(\.title)) { pickExercise($0) }
            case .meals:
                VStack(spacing: 8) {
                    Button("Use these meals") { useSuggestedMeals() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Build my own meals") { showMealEditor = true }
                        .font(.display(17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button("Keep my current meals") { keepCurrentMeals() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            case .done:
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .background(Theme.bg)
    }

    private func chipRow(_ chips: [String], tap: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button(chip) { tap(chip) }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.accent, in: Capsule())
                }
            }
        }
    }

    private func start() {
        guard !started else { return }
        started = true
        if age <= 0 { age = 0 }
        answers.age = age > 0 ? age : nil
        answers.weightKg = weights.last?.weightKg
        answers.goal = Goal(rawValue: goalRaw)
        prompts = CoachPlanner.prompts(age: age, weightKg: weights.last?.weightKg, unit: unit)
        messages.append(CoachMessage(fromCoach: true, text: CoachPlanner.opener(age: age, weightKg: weights.last?.weightKg, unit: unit)))
        if let first = prompts.first {
            messages.append(CoachMessage(fromCoach: true, text: first.text))
        }
    }

    private func submit(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard choice == .questions, !text.isEmpty, let prompt = currentPrompt else { return }
        draft = ""
        messages.append(CoachMessage(fromCoach: false, text: text))
        if let problem = CoachPlanner.accept(text, step: prompt.step, unit: unit, into: &answers) {
            messages.append(CoachMessage(fromCoach: true, text: problem))
            if problem == String(localized: "Spotter is for people 13 and older.") {
                choice = .done
            }
            return
        }
        stepIndex += 1
        if let next = currentPrompt {
            messages.append(CoachMessage(fromCoach: true, text: next.text))
            return
        }
        finish()
    }

    private func finish() {
        if answers.age == nil { answers.age = age > 0 ? age : nil }
        if answers.weightKg == nil { answers.weightKg = weights.last?.weightKg }
        let built = CoachPlanner.build(
            answers: answers,
            place: TrainingPlace(rawValue: placeRaw) ?? .home,
            level: Level(rawValue: levelRaw) ?? .beginner,
            isPro: store.isPro,
            heightCm: heightCm,
            unit: unit
        )
        if let savedAge = built.age { age = savedAge }
        if let goal = built.goal { goalRaw = goal.rawValue }
        if let kg = built.weightKg {
            let latest = weights.last?.weightKg ?? -1
            if abs(latest - kg) > 0.05 {
                modelContext.insert(WeightEntry(weightKg: kg))
            }
        }
        pending = built
        messages.append(CoachMessage(fromCoach: true, text: built.message))
        choice = built.days.isEmpty ? .done : .offer
        Haptics.success()
    }

    private func useSuggested() {
        guard let pending else { return }
        CoachPlanner.apply(pending)
        messages.append(CoachMessage(fromCoach: false, text: String(localized: "Use this plan")))
        messages.append(CoachMessage(fromCoach: true, text: String(localized: "Saved. Today's exercises are on the Today tab, and the meals are on Meals.")))
        SpotterAnalytics.log("coach_plan", ["choice": "suggested", "days": "\(pending.days.count)"])
        choice = .done
        Haptics.success()
    }

    private func startCustom() {
        messages.append(CoachMessage(fromCoach: false, text: String(localized: "Choose my own")))
        messages.append(CoachMessage(fromCoach: true, text: String(localized: "Pick an exercise plan. I'll ask about meals after that.")))
        choice = .exercises
    }

    private func pickExercise(_ title: String) {
        let place = TrainingPlace(rawValue: placeRaw) ?? .home
        let match = CoachPlanner.exerciseChoices(place: place, isPro: store.isPro).first { $0.title == title }
        messages.append(CoachMessage(fromCoach: false, text: title))
        if let ids = match?.ids, let pending {
            let dates = pending.days.map(\.0)
            CoachPlanner.applyExercises(CoachPlanner.schedule(ids, on: dates), focus: match?.focus ?? .fullBody)
            let names = ids.map { ExerciseLibrary.spec($0).name }
            messages.append(CoachMessage(fromCoach: true, text: String(localized: "Exercises saved: \(names.joined(separator: ", ")).\n\nUse the meals I suggested, build your own, or keep the meals you already have?")))
        } else {
            messages.append(CoachMessage(fromCoach: true, text: String(localized: "I'll leave your workout as it is.\n\nUse the meals I suggested, build your own, or keep the meals you already have?")))
        }
        choice = .meals
    }

    private func useSuggestedMeals() {
        guard let pending else { return }
        CoachPlanner.applyMeals(pending)
        messages.append(CoachMessage(fromCoach: false, text: String(localized: "Use these meals")))
        messages.append(CoachMessage(fromCoach: true, text: String(localized: "Meals are on the Meals tab. You can still edit any product there.")))
        SpotterAnalytics.log("coach_plan", ["choice": "custom", "days": "\(pending.days.count)"])
        choice = .done
        Haptics.success()
    }

    private func keepCurrentMeals() {
        messages.append(CoachMessage(fromCoach: false, text: String(localized: "Keep my current meals")))
        messages.append(CoachMessage(fromCoach: true, text: String(localized: "Your meals stay as they are. The workout choice is on Today.")))
        choice = .done
    }

    private func mealEditorClosed() {
        guard choice == .meals else { return }
        messages.append(CoachMessage(fromCoach: true, text: String(localized: "If you saved foods, they are on the Meals tab. The workout choice is on Today.")))
        choice = .done
    }
}

private enum CoachChoice {
    case questions, offer, exercises, meals, done
}

struct CoachMessage: Identifiable {
    let id = UUID()
    var fromCoach: Bool
    var text: String
}
