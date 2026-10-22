import SwiftUI
import SwiftData
import Charts

enum HistoryTab: String, CaseIterable, Identifiable {
    case workouts, weight, exercises
    var id: String { rawValue }
    var title: String {
        switch self {
        case .workouts: return String(localized: "Workouts")
        case .weight: return String(localized: "Weight")
        case .exercises: return String(localized: "Exercises")
        }
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutLog.date, order: .reverse) private var logs: [WorkoutLog]
    @Query(sort: \SetLog.date, order: .reverse) private var sets: [SetLog]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @AppStorage("goalWeightKg") private var goalWeightKg = 0.0
    @AppStorage("heightCm") private var heightCm = 0.0
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue
    @State private var tab: HistoryTab
    @State private var showWeightLog = false

    init(initialTab: HistoryTab = .workouts) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("History", selection: $tab) {
                ForEach(HistoryTab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: tab) { _, new in
                SpotterAnalytics.click("history_tab", screen: "history", ["tab": new.rawValue])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            switch tab {
            case .workouts: workoutList
            case .weight: weightList
            case .exercises: exerciseList
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showWeightLog) { WeightLogSheet() }
    }

    private var workoutList: some View {
        Group {
            if logs.isEmpty {
                empty(symbol: "figure.run", title: "No workouts yet", message: "Finished sessions show up here with the date, reps and form score.")
            } else {
                List {
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(log.title).font(.display(16, weight: .bold)).foregroundStyle(.white)
                                Spacer()
                                Text("\(log.avgFormScore)")
                                    .font(.display(15, weight: .heavy))
                                    .foregroundStyle(Theme.scoreColor(log.avgFormScore))
                            }
                            Text(log.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                            HStack(spacing: 10) {
                                Text("\(log.totalReps) reps")
                                Text("\(log.setCount) sets")
                                Text(duration(log.durationSeconds))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Theme.surface)
                    }
                    .onDelete(perform: deleteWorkouts)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var weightSnapshot: WeightTrend.Snapshot { WeightTrend.snapshot(from: weights) }
    private var weightUnit: Measure.Weight { Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms }

    private var weightList: some View {
        Group {
            if weights.isEmpty {
                VStack(spacing: 16) {
                    empty(symbol: "scalemass", title: "No weigh-ins yet", message: "Log your weight to see how this week and this month are moving.")
                    Button("Log weight") {
                        SpotterAnalytics.click("log_weight", screen: "history")
                        showWeightLog = true
                    }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 20)
                }
            } else {
                List {
                    Section {
                        weightSummary
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    }
                    Section {
                        ForEach(weights) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(Measure.format(weightUnit.fromKilograms(entry.weightKg))) \(weightUnit.symbol)")
                                        .font(.display(17, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if Calendar.current.isDateInToday(entry.date) {
                                    Text("Today").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                                }
                            }
                            .listRowBackground(Theme.surface)
                        }
                        .onDelete(perform: deleteWeights)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var weightSummary: some View {
        let snap = weightSnapshot
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(snap.latest.map { Measure.format(weightUnit.fromKilograms($0.weightKg)) } ?? "–")
                    .font(.display(34, weight: .heavy))
                    .foregroundStyle(.white)
                Text(weightUnit.symbol).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Log") {
                    SpotterAnalytics.click("log_weight", screen: "history", ["source": "summary"])
                    showWeightLog = true
                }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
            }
            HStack(spacing: 10) {
                changeTile("This week", snap.weekDelta, unit: weightUnit)
                changeTile("This month", snap.monthDelta, unit: weightUnit)
            }
            if goalWeightKg > 0, let latest = snap.latest {
                let gap = weightUnit.fromKilograms(latest.weightKg - goalWeightKg)
                Text(gap > 0.1
                     ? String(localized: "\(Measure.format(gap)) \(weightUnit.symbol) to your \(Measure.format(weightUnit.fromKilograms(goalWeightKg))) \(weightUnit.symbol) goal")
                     : String(localized: "At or under your \(Measure.format(weightUnit.fromKilograms(goalWeightKg))) \(weightUnit.symbol) goal"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            if let latest = snap.latest {
                BMIReadout(weightKg: latest.weightKg, heightCm: heightCm) {
                    showWeightLog = true
                }
            }
            if snap.sorted.count >= 2, let first = snap.sorted.first?.date, let last = snap.sorted.last?.date {
                let band = BodyRange.healthyWeightKg(heightCm: heightCm)
                Chart {
                    if let band {
                        RectangleMark(
                            xStart: .value("Start", first),
                            xEnd: .value("End", last),
                            yStart: .value("Low", weightUnit.fromKilograms(band.low)),
                            yEnd: .value("High", weightUnit.fromKilograms(band.high))
                        )
                        .foregroundStyle(Theme.accent.opacity(0.18))
                    }
                    ForEach(snap.sorted) { entry in
                        LineMark(x: .value("Date", entry.date), y: .value(weightUnit.symbol, weightUnit.fromKilograms(entry.weightKg)))
                            .foregroundStyle(Theme.accent)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", entry.date), y: .value(weightUnit.symbol, weightUnit.fromKilograms(entry.weightKg)))
                            .foregroundStyle(.white)
                            .symbolSize(40)
                    }
                }
                .chartYScale(domain: chartDomain(snap.sorted.map { weightUnit.fromKilograms($0.weightKg) },
                                                 extra: band.map { [weightUnit.fromKilograms($0.low), weightUnit.fromKilograms($0.high)] } ?? []))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel().foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 180)
                if heightCm > 0 {
                    Text("The green band is the healthy weight for your height.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func changeTile(_ title: LocalizedStringKey, _ delta: Double?, unit: Measure.Weight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
            Text(WeightTrend.changeLabel(delta, unit: unit))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(deltaColor(delta))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var exerciseDays: [ExerciseDay] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: sets) { set in
            "\(set.exerciseID)-\(cal.startOfDay(for: set.date).timeIntervalSinceReferenceDate)"
        }
        return groups.map { _, list in
            let sample = list[0]
            return ExerciseDay(
                id: "\(sample.exerciseID)-\(cal.startOfDay(for: sample.date).timeIntervalSinceReferenceDate)",
                name: sample.exerciseName,
                symbol: ExerciseLibrary.spec(sample.exerciseID).symbol,
                date: list.map(\.date).max() ?? sample.date,
                reps: list.reduce(0) { $0 + $1.reps },
                sets: list.count,
                score: list.map(\.avgFormScore).max() ?? 0,
                load: list.map(\.weightKg).max() ?? 0
            )
        }
        .sorted { $0.date > $1.date }
    }

    private var exerciseList: some View {
        Group {
            if sets.isEmpty {
                empty(symbol: "dumbbell", title: "No exercises yet", message: "Each exercise you finish is kept here with the reps, load and form score.")
            } else {
                List(exerciseDays) { day in
                    HStack(spacing: 12) {
                        Image(systemName: day.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 36, height: 36)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.name).font(.display(16, weight: .bold)).foregroundStyle(.white)
                            Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                            HStack(spacing: 8) {
                                Text("\(day.sets) sets")
                                if day.reps > 0 { Text("· \(day.reps) reps") }
                                if day.load > 0 { Text("· \(Measure.format(weightUnit.fromKilograms(day.load))) \(weightUnit.symbol)") }
                            }
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text("\(day.score)")
                            .font(.display(16, weight: .heavy))
                            .foregroundStyle(Theme.scoreColor(day.score))
                    }
                    .listRowBackground(Theme.surface)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func empty(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 48)
            Text(title).font(.display(22, weight: .bold)).foregroundStyle(.white)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deleteWorkouts(at offsets: IndexSet) {
        for index in offsets {
            let log = logs[index]
            for set in sets where set.sessionID == log.id {
                modelContext.delete(set)
            }
            modelContext.delete(log)
        }
        try? modelContext.save()
        SpotterAnalytics.click("delete_workout", screen: "history")
    }

    private func deleteWeights(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(weights[index])
        }
        try? modelContext.save()
        SpotterAnalytics.click("delete_weigh_in", screen: "history")
    }

    private func duration(_ seconds: Int) -> String {
        if seconds < 60 { return String(localized: "\(seconds)s") }
        return String(localized: "\(seconds / 60) min")
    }

    private func deltaColor(_ delta: Double?) -> Color {
        guard let delta, abs(delta) >= 0.05 else { return Theme.textSecondary }
        return delta < 0 ? Theme.accent : Theme.warn
    }

    private func chartDomain(_ values: [Double], extra: [Double] = []) -> ClosedRange<Double> {
        let all = values + extra
        let low = (all.min() ?? 0) - 1
        let high = (all.max() ?? 0) + 1
        return low < high ? low...high : (low - 1)...(high + 1)
    }
}

struct BMIReadout: View {
    let weightKg: Double
    let heightCm: Double
    var goalKg: Double? = nil
    var onAddHeight: () -> Void

    @AppStorage("goalWeightKg") private var storedGoalKg = 0.0
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue
    @AppStorage("heightUnit") private var heightUnitRaw = Measure.Height.centimeters.rawValue

    private var weightUnit: Measure.Weight { Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms }
    private var heightUnit: Measure.Height { Measure.Height(rawValue: heightUnitRaw) ?? .centimeters }
    private var goal: Double { goalKg ?? storedGoalKg }

    var body: some View {
        if let report = BodyRange.assess(weightKg: weightKg, heightCm: heightCm, goalKg: goal, unit: weightUnit) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BMI \(BMI.format(report.bmi))").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                        Text(report.verdict)
                            .font(.display(18, weight: .bold))
                            .foregroundStyle(toneColor(report.tone))
                    }
                    Spacer()
                    Text(heightUnit.text(cm: heightCm))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(report.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                rangeBar(report)
            }
            .padding(12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Button(action: {
                SpotterAnalytics.click("add_height", screen: "bmi")
                onAddHeight()
            }) {
                HStack {
                    Text("Add your height to see your range")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func rangeBar(_ report: BodyRange.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(BodyRange.segments) { segment in
                            Rectangle().fill(toneColor(segment.tone).opacity(0.9))
                                .frame(width: width * segment.fraction)
                        }
                    }
                    .clipShape(Capsule())
                    if let goalMarker = report.goalMarker {
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 2, height: 18)
                            .offset(x: width * goalMarker - 1)
                    }
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(toneColor(report.tone), lineWidth: 3))
                        .offset(x: min(max(0, width * report.marker - 8), width - 16))
                }
            }
            .frame(height: 18)
            HStack(spacing: 10) {
                legendDot(Theme.warn, "Under")
                legendDot(Theme.accent, "In range")
                legendDot(Theme.warn, "Over")
                legendDot(Theme.bad, "High")
            }
            HStack {
                Text("You")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                if report.goalMarker != nil {
                    Text("White tick is your goal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func legendDot(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textTertiary)
        }
    }

    private func toneColor(_ tone: BodyRange.Tone) -> Color {
        switch tone {
        case .under: return Theme.warn
        case .healthy: return Theme.accent
        case .over: return Theme.warn
        case .high: return Theme.bad
        }
    }
}

private struct ExerciseDay: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let date: Date
    let reps: Int
    let sets: Int
    let score: Int
    let load: Double
}

struct WeightLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    @AppStorage("goalWeightKg") private var goalWeightKg = 0.0
    @AppStorage("heightCm") private var heightCm = 0.0
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue
    @AppStorage("heightUnit") private var heightUnitRaw = Measure.Height.centimeters.rawValue

    @State private var text = ""
    @State private var heightText = ""
    @State private var feetText = ""
    @State private var inchesText = ""
    @State private var goalText = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var weightUnit: Measure.Weight { Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms }
    private var heightUnit: Measure.Height { Measure.Height(rawValue: heightUnitRaw) ?? .centimeters }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldHeader("Body weight") {
                            unitPicker(selection: $weightUnitRaw, options: Measure.Weight.allCases.map { ($0.rawValue, $0.symbol) })
                        }
                        HStack(alignment: .firstTextBaseline) {
                            TextField(weightUnit.placeholder, text: $text)
                                .keyboardType(.decimalPad)
                                .focused($focused)
                                .font(.display(42, weight: .heavy))
                                .foregroundStyle(.white)
                            Text(weightUnit.symbol).font(.title3.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        fieldHeader("Height") {
                            unitPicker(selection: $heightUnitRaw, options: Measure.Height.allCases.map { ($0.rawValue, $0.symbol) })
                        }
                        if heightUnit == .centimeters {
                            HStack(alignment: .firstTextBaseline) {
                                TextField("175", text: $heightText)
                                    .keyboardType(.decimalPad)
                                    .font(.display(28, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("cm").font(.body.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            }
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                HStack(alignment: .firstTextBaseline) {
                                    TextField("5", text: $feetText)
                                        .keyboardType(.numberPad)
                                        .font(.display(28, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text("ft").font(.body.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                }
                                HStack(alignment: .firstTextBaseline) {
                                    TextField("9", text: $inchesText)
                                        .keyboardType(.numberPad)
                                        .font(.display(28, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text("in").font(.body.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    if let kg = kilograms(from: text), let cm = centimetersFromFields() {
                        BMIReadout(weightKg: kg, heightCm: cm, goalKg: liveGoalKg) {}
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Goal weight").eyebrow()
                        HStack(alignment: .firstTextBaseline) {
                            TextField("Optional", text: $goalText)
                                .keyboardType(.decimalPad)
                                .font(.display(28, weight: .bold))
                                .foregroundStyle(.white)
                            Text(weightUnit.symbol).font(.body.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        }
                        Text("Choose kilograms or pounds, and centimetres or feet and inches. BMI uses the same numbers either way. Healthy for most adults is 18.5–24.9.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if let error {
                        Text(error).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.bad)
                    }
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        SpotterAnalytics.click("weigh_in_cancel", screen: "weigh_in")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        SpotterAnalytics.click("weigh_in_save", screen: "weigh_in")
                        save()
                    }
                        .fontWeight(.bold)
                }
            }
            .onAppear(perform: prefill)
            .onChange(of: weightUnitRaw) { old, new in
                SpotterAnalytics.click("weight_unit", screen: "weigh_in", ["value": new])
                convertWeightFields(from: old, to: new)
            }
            .onChange(of: heightUnitRaw) { old, new in
                SpotterAnalytics.click("height_unit", screen: "weigh_in", ["value": new])
                convertHeightFields(from: old, to: new)
            }
        }
        .presentationDetents([.large])
    }

    private func fieldHeader<Picker: View>(_ title: String, @ViewBuilder picker: () -> Picker) -> some View {
        HStack {
            Text(title).eyebrow()
            Spacer()
            picker()
        }
    }

    private func unitPicker(selection: Binding<String>, options: [(String, String)]) -> some View {
        Picker("Unit", selection: selection) {
            ForEach(options, id: \.0) { value, label in
                Text(label).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 140)
    }

    private var liveGoalKg: Double {
        if goalText.trimmingCharacters(in: .whitespaces).isEmpty { return 0 }
        if let shown = Measure.number(goalText), weightUnit.accepts(shown) {
            return weightUnit.toKilograms(shown)
        }
        return goalWeightKg
    }

    private func prefill() {
        focused = true
        if text.isEmpty, let latest = entries.first {
            text = Measure.format(weightUnit.fromKilograms(latest.weightKg))
        }
        if goalText.isEmpty, goalWeightKg > 0 {
            goalText = Measure.format(weightUnit.fromKilograms(goalWeightKg))
        }
        guard heightCm > 0 else { return }
        if heightUnit == .centimeters {
            if heightText.isEmpty { heightText = Measure.format(heightCm, places: 1) }
        } else if feetText.isEmpty && inchesText.isEmpty {
            let parts = Measure.Height.parts(cm: heightCm)
            feetText = String(parts.feet)
            inchesText = String(parts.inches)
        }
    }

    private func convertWeightFields(from oldRaw: String, to newRaw: String) {
        guard let from = Measure.Weight(rawValue: oldRaw), let to = Measure.Weight(rawValue: newRaw), from != to else { return }
        text = convertedWeight(text, from: from, to: to)
        goalText = convertedWeight(goalText, from: from, to: to)
    }

    private func convertedWeight(_ raw: String, from: Measure.Weight, to: Measure.Weight) -> String {
        guard let value = Measure.number(raw) else { return raw }
        return Measure.format(to.fromKilograms(from.toKilograms(value)))
    }

    private func convertHeightFields(from oldRaw: String, to newRaw: String) {
        guard let from = Measure.Height(rawValue: oldRaw), let to = Measure.Height(rawValue: newRaw), from != to else { return }
        switch (from, to) {
        case (.centimeters, .feet):
            guard let cm = Measure.number(heightText) else { return }
            let parts = Measure.Height.parts(cm: cm)
            feetText = String(parts.feet)
            inchesText = String(parts.inches)
        case (.feet, .centimeters):
            let cm = Measure.Height.centimeters(feet: Measure.number(feetText) ?? 0, inches: Measure.number(inchesText) ?? 0)
            guard cm > 0 else { return }
            heightText = Measure.format(cm, places: 1)
        default:
            break
        }
    }

    private func save() {
        guard let shown = Measure.number(text), weightUnit.accepts(shown) else {
            error = String(localized: "Enter a weight between \(weightUnit.rangeDescription).")
            return
        }
        let kg = weightUnit.toKilograms(shown)

        if heightIsBlank {
            heightCm = 0
        } else if let cm = centimetersFromFields(), Measure.Height.accepts(cm: cm) {
            heightCm = cm
        } else {
            error = heightUnit == .centimeters
                ? String(localized: "Enter a height between 90 and 250 cm.")
                : String(localized: "Enter a height like 5 ft 9 in.")
            return
        }

        if goalText.trimmingCharacters(in: .whitespaces).isEmpty {
            goalWeightKg = 0
        } else if let shownGoal = Measure.number(goalText), weightUnit.accepts(shownGoal) {
            goalWeightKg = weightUnit.toKilograms(shownGoal)
        } else {
            error = String(localized: "Enter a goal between \(weightUnit.rangeDescription), or leave it blank.")
            return
        }

        if let today = entries.first(where: { Calendar.current.isDateInToday($0.date) }) {
            today.weightKg = kg
            today.date = .now
        } else {
            modelContext.insert(WeightEntry(weightKg: kg))
        }
        try? modelContext.save()
        SpotterAnalytics.log("weight_logged", [
            "unit": weightUnit.rawValue,
            "has_goal": goalWeightKg > 0 ? "true" : "false"
        ])
        Haptics.success()
        dismiss()
    }

    private var heightIsBlank: Bool {
        switch heightUnit {
        case .centimeters:
            return heightText.trimmingCharacters(in: .whitespaces).isEmpty
        case .feet:
            return feetText.trimmingCharacters(in: .whitespaces).isEmpty && inchesText.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func kilograms(from raw: String) -> Double? {
        guard let shown = Measure.number(raw) else { return nil }
        return weightUnit.toKilograms(shown)
    }

    private func centimetersFromFields() -> Double? {
        switch heightUnit {
        case .centimeters:
            return Measure.number(heightText)
        case .feet:
            let feet = Measure.number(feetText) ?? 0
            let inches = Measure.number(inchesText) ?? 0
            let cm = Measure.Height.centimeters(feet: feet, inches: inches)
            return cm > 0 ? cm : nil
        }
    }
}
