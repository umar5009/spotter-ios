import SwiftUI
import SwiftData
import Charts

struct ProgressScreen: View {
    @Query(sort: \WorkoutLog.date) private var logs: [WorkoutLog]
    @Query(sort: \SetLog.date) private var sets: [SetLog]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @AppStorage("goalWeightKg") private var goalWeightKg = 0.0
    @AppStorage("heightCm") private var heightCm = 0.0
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue
    @State private var showWeightLog = false
    @State private var showTarget = false

    private var totalReps: Int { logs.reduce(0) { $0 + $1.totalReps } }
    private var avgForm: Int { logs.isEmpty ? 0 : logs.reduce(0) { $0 + $1.avgFormScore } / logs.count }
    private var streak: Int { Streak.current(from: logs.map(\.date)) }
    private var bestStreak: Int { Streak.longest(from: logs.map(\.date)) }
    private var weightSnapshot: WeightTrend.Snapshot { WeightTrend.snapshot(from: weights) }
    private var weightUnit: Measure.Weight { Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms }

    private var topFixes: [(String, Int)] {
        var counts: [String: Int] = [:]
        for s in sets.suffix(200) { for f in s.faults { counts[f, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }
    }

    private struct ExerciseStat: Identifiable {
        let id: String
        let name: String
        let bestScore: Int
        let totalReps: Int
        let heaviest: Double
        let trend: Int
    }

    private var exerciseStats: [ExerciseStat] {
        Dictionary(grouping: sets, by: \.exerciseID).map { id, list in
            let scores = list.map(\.avgFormScore)
            let firstHalf = scores.prefix(max(1, scores.count / 2))
            let secondHalf = scores.suffix(max(1, scores.count / 2))
            let trend = secondHalf.reduce(0, +) / max(1, secondHalf.count) - firstHalf.reduce(0, +) / max(1, firstHalf.count)
            return ExerciseStat(id: id, name: list.first?.exerciseName ?? id,
                                bestScore: scores.max() ?? 0,
                                totalReps: list.reduce(0) { $0 + $1.reps },
                                heaviest: list.map(\.weightKg).max() ?? 0,
                                trend: trend)
        }
        .sorted { $0.totalReps > $1.totalReps }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BadgeBoardView(logs: logs, weights: weights) {
                        showTarget = true
                    }
                    if logs.isEmpty && weights.isEmpty {
                        emptyState
                    } else {
                        weightCard
                        if goalWeightKg > 0 { WeightLossCard() }
                        if !logs.isEmpty {
                            HStack(spacing: 10) {
                                stat("\(logs.count)", "workouts", "figure.run")
                                stat("\(totalReps)", "reps", "repeat")
                                if bestStreak > streak {
                                    stat("\(streak)", "streak · best \(bestStreak)", "flame.fill")
                                } else {
                                    stat("\(streak)", "day streak", "flame.fill")
                                }
                            }
                            formChart
                            if !topFixes.isEmpty { fixesCard }
                            exercisesCard
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .trackClick("open_history", screen: "progress")
                }
            }
            .sheet(isPresented: $showWeightLog) { WeightLogSheet() }
            .sheet(isPresented: $showTarget) { WeightLossTargetSheet() }
        }
    }

    private var weightCard: some View {
        let snap = weightSnapshot
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Body weight").eyebrow()
                    Spacer()
                    NavigationLink {
                        HistoryView(initialTab: .weight)
                    } label: {
                        Text("History").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                    }
                    .trackClick("open_weight_history", screen: "progress")
                }
                if let latest = snap.latest {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Measure.format(weightUnit.fromKilograms(latest.weightKg))).font(.display(32, weight: .heavy)).foregroundStyle(.white)
                        Text(weightUnit.symbol).foregroundStyle(Theme.textSecondary)
                    }
                    HStack(spacing: 10) {
                        weightTile("This week", snap.weekDelta)
                        weightTile("This month", snap.monthDelta)
                    }
                    BMIReadout(weightKg: latest.weightKg, heightCm: heightCm) {
                        SpotterAnalytics.click("log_weight", screen: "progress", ["source": "add_height"])
                        showWeightLog = true
                    }
                    if goalWeightKg <= 0 {
                        Button("Set a loss target") {
                            SpotterAnalytics.click("open_loss_target", screen: "progress", ["source": "weight"])
                            showTarget = true
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    }
                    Button("Log weight") {
                        SpotterAnalytics.click("log_weight", screen: "progress")
                        showWeightLog = true
                    }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Text("Weigh in to track loss by week and by month.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    if goalWeightKg <= 0 {
                        Button("Set a loss target") {
                            SpotterAnalytics.click("open_loss_target", screen: "progress", ["source": "weight"])
                            showTarget = true
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    }
                    Button("Log weight") {
                        SpotterAnalytics.click("log_weight", screen: "progress")
                        showWeightLog = true
                    }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private func weightTile(_ title: LocalizedStringKey, _ delta: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
            Text(WeightTrend.changeLabel(delta, unit: weightUnit))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(weightColor(delta))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func weightColor(_ delta: Double?) -> Color {
        guard let delta, abs(delta) >= 0.05 else { return Theme.textSecondary }
        return delta < 0 ? Theme.accent : Theme.warn
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 12)
            Text("Your progress lives here").font(.display(22, weight: .bold)).foregroundStyle(.white)
            Text("Finish your first coached workout to see your form score trend, personal bests and the one fix that will improve you most.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 32)
        }
    }

    private var formChart: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Form score trend").eyebrow()
                    Spacer()
                    Text("\(avgForm)").font(.display(26, weight: .heavy)).foregroundStyle(Theme.scoreColor(avgForm))
                    Text("avg").font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                }
                Chart(logs.suffix(20)) { log in
                    AreaMark(x: .value("Date", log.date), y: .value("Form", log.avgFormScore))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Date", log.date), y: .value("Form", log.avgFormScore))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", log.date), y: .value("Form", log.avgFormScore))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(30)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel().foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private var fixesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your top fixes").eyebrow(Theme.warn)
                ForEach(Array(topFixes.enumerated()), id: \.offset) { i, fix in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.display(15, weight: .heavy)).foregroundStyle(.black)
                            .frame(width: 26, height: 26).background(Theme.warn, in: Circle())
                        Text(fix.0).font(.display(16, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("×\(fix.1)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private var exercisesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By exercise").eyebrow()
            ForEach(exerciseStats) { s in
                Card(padding: 14) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.name).font(.display(16, weight: .bold)).foregroundStyle(.white)
                            HStack(spacing: 6) {
                                Text("\(s.totalReps) reps").foregroundStyle(Theme.textSecondary)
                                if s.heaviest > 0 { Text("· best \(Measure.format(weightUnit.fromKilograms(s.heaviest))) \(weightUnit.symbol)").foregroundStyle(Theme.textSecondary) }
                            }
                            .font(.subheadline)
                        }
                        Spacer()
                        if s.trend != 0 {
                            Label("\(abs(s.trend))", systemImage: s.trend > 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(s.trend > 0 ? Theme.accent : Theme.bad)
                        }
                        ScoreRing(score: s.bestScore, size: 44, lineWidth: 4)
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
            Text(value).font(.display(24, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
