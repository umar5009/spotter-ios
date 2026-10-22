import SwiftData
import SwiftUI

/// A GitHub-style training calendar. Darker squares are higher-scoring days.
enum StreakCalendar {
    struct Column: Identifiable {
        let id: Date
        let month: String?
        let days: [Day]
    }

    struct Day: Identifiable {
        let date: Date
        let points: Int
        let level: Int
        let badge: Bool
        let isFuture: Bool
        var id: Date { date }
    }

    struct ExerciseBlock: Identifiable {
        let id: String
        let name: String
        let sets: [SetLog]
    }

    struct Report {
        let date: Date
        let points: Int
        let reps: Int
        let holdSeconds: Int
        let minutes: Int
        let form: Int
        let workouts: [WorkoutLog]
        let exercises: [ExerciseBlock]
        let weightKg: Double?
        let badge: Bool
        let streakLength: Int
        let isFuture: Bool
        let isAllTimeBest: Bool
    }

    /// Every trained day, highest score first.
    static func rankedDays(logs: [WorkoutLog], sets: [SetLog]) -> [Day] {
        let calendar = Calendar.current
        let points = pointsByDay(logs: logs, sets: sets, calendar: calendar)
        let badges = badgeDays(points: points, calendar: calendar)
        let positive = points.values.filter { $0 > 0 }.sorted()
        return points.compactMap { date, score in
            guard score > 0 else { return nil }
            return Day(date: date, points: score, level: level(score, among: positive),
                       badge: badges.contains(date), isFuture: false)
        }
        .sorted { lhs, rhs in
            if lhs.points != rhs.points { return lhs.points > rhs.points }
            return lhs.date > rhs.date
        }
    }

    static func columns(logs: [WorkoutLog], sets: [SetLog], weeks: Int = 26, now: Date = .now) -> [Column] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let points = pointsByDay(logs: logs, sets: sets, calendar: calendar)
        let badges = badgeDays(points: points, calendar: calendar)
        let positive = points.values.filter { $0 > 0 }.sorted()

        let mondayIndex = PlanBuilder.mondayIndex(today, calendar: calendar)
        guard let thisMonday = calendar.date(byAdding: .day, value: -mondayIndex, to: today),
              let firstMonday = calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: thisMonday) else { return [] }

        var columns: [Column] = []
        var previousMonth: Int?
        for week in 0..<weeks {
            guard let monday = calendar.date(byAdding: .day, value: week * 7, to: firstMonday) else { continue }
            let month = calendar.component(.month, from: monday)
            let showMonth = month != previousMonth
            previousMonth = month
            let days: [Day] = (0..<7).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: monday) else { return nil }
                let score = points[date] ?? 0
                return Day(date: date, points: score, level: level(score, among: positive),
                           badge: badges.contains(date), isFuture: date > today)
            }
            columns.append(Column(id: monday, month: showMonth ? monday.formatted(.dateTime.month(.abbreviated)) : nil, days: days))
        }
        return columns
    }

    static func report(for date: Date, logs: [WorkoutLog], sets: [SetLog], weights: [WeightEntry]) -> Report {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: .now)
        let points = pointsByDay(logs: logs, sets: sets, calendar: calendar)
        let badges = badgeDays(points: points, calendar: calendar)
        let best = points.values.max() ?? 0
        let dayLogs = logs.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
        let daySets = sets.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.setNumber < $1.setNumber }
        var order: [String] = []
        var grouped: [String: [SetLog]] = [:]
        for set in daySets {
            if grouped[set.exerciseName] == nil { order.append(set.exerciseName) }
            grouped[set.exerciseName, default: []].append(set)
        }
        let trained = Set(points.filter { $0.value > 0 }.map(\.key))
        let weight = weights.first { calendar.isDate($0.date, inSameDayAs: day) }?.weightKg
        let formSamples = dayLogs.map(\.avgFormScore).filter { $0 > 0 }
        let form = formSamples.isEmpty ? 0 : formSamples.reduce(0, +) / formSamples.count
        return Report(
            date: day,
            points: points[day] ?? 0,
            reps: daySets.reduce(0) { $0 + $1.reps },
            holdSeconds: daySets.reduce(0) { $0 + $1.holdSeconds },
            minutes: max(0, dayLogs.reduce(0) { $0 + $1.durationSeconds } / 60),
            form: form,
            workouts: dayLogs,
            exercises: order.map { ExerciseBlock(id: $0, name: $0, sets: grouped[$0] ?? []) },
            weightKg: weight,
            badge: badges.contains(day),
            streakLength: streakLength(containing: day, trained: trained, calendar: calendar),
            isFuture: day > today,
            isAllTimeBest: (points[day] ?? 0) > 0 && (points[day] ?? 0) == best
        )
    }

    /// Reps and holds, weighted by form. An 8-rep set scored 80 is 64 points.
    static func points(reps: Int, holdSeconds: Int, form: Int) -> Int {
        let quality = max(form, 1)
        return reps * quality / 10 + (holdSeconds / 5) * quality / 10
    }

    private static func pointsByDay(logs: [WorkoutLog], sets: [SetLog], calendar: Calendar) -> [Date: Int] {
        var totals: [Date: Int] = [:]
        for set in sets {
            let day = calendar.startOfDay(for: set.date)
            totals[day, default: 0] += points(reps: set.reps, holdSeconds: set.holdSeconds, form: set.avgFormScore)
        }
        for log in logs {
            let day = calendar.startOfDay(for: log.date)
            if totals[day] == nil || totals[day] == 0 {
                let fallback = max(log.totalReps, log.setCount) * max(log.avgFormScore, 1) / 10
                totals[day] = max(totals[day] ?? 0, max(fallback, 1))
            }
        }
        return totals
    }

    /// The highest-scoring day of each streak, plus the best day overall.
    private static func badgeDays(points: [Date: Int], calendar: Calendar) -> Set<Date> {
        let trained = points.filter { $0.value > 0 }.map(\.key).sorted()
        guard !trained.isEmpty else { return [] }
        var badges = Set<Date>()
        if let best = points.values.max() {
            badges.formUnion(trained.filter { points[$0] == best })
        }
        var run: [Date] = []
        func closeRun() {
            guard run.count >= 2 else { run = []; return }
            let best = run.map { points[$0] ?? 0 }.max() ?? 0
            badges.formUnion(run.filter { (points[$0] ?? 0) == best })
            run = []
        }
        for day in trained {
            if let previous = run.last, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run.append(day)
            } else {
                closeRun()
                run = [day]
            }
        }
        closeRun()
        return badges
    }

    private static func streakLength(containing date: Date, trained: Set<Date>, calendar: Calendar) -> Int {
        guard trained.contains(date) else { return 0 }
        var count = 1
        var day = date
        while let previous = calendar.date(byAdding: .day, value: -1, to: day), trained.contains(previous) {
            count += 1
            day = previous
        }
        day = date
        while let next = calendar.date(byAdding: .day, value: 1, to: day), trained.contains(next) {
            count += 1
            day = next
        }
        return count
    }

    private static func level(_ points: Int, among positive: [Int]) -> Int {
        guard points > 0, let peak = positive.last, peak > 0 else { return 0 }
        if points >= peak { return 4 }
        let q1 = positive[positive.count / 4]
        let q2 = positive[positive.count / 2]
        if points <= Swift.max(q1, 1) { return 1 }
        if points <= q2 { return 2 }
        return 3
    }

    static func color(level: Int) -> Color {
        switch level {
        case 1: return Theme.accent.opacity(0.30)
        case 2: return Theme.accent.opacity(0.50)
        case 3: return Theme.accent.opacity(0.74)
        case 4: return Theme.accent
        default: return Color.white.opacity(0.07)
        }
    }
}

struct StreakCalendarCard: View {
    let logs: [WorkoutLog]
    let sets: [SetLog]
    let weights: [WeightEntry]

    @State private var selected: StreakCalendar.Day?

    private let cell: CGFloat = 14
    private let pitch: CGFloat = 18
    private let gap: CGFloat = 3
    private var columns: [StreakCalendar.Column] { StreakCalendar.columns(logs: logs, sets: sets) }
    private var streak: Int { Streak.current(from: logs.map(\.date)) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Streaks").eyebrow()
                    Spacer()
                    Text(streak == 0 ? String(localized: "No streak yet") : String(localized: "\(streak) day streak"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(streak == 0 ? Theme.textTertiary : Theme.warn)
                }
                grid
                legend
            }
        }
        .sheet(item: $selected) { day in
            DayReportView(report: StreakCalendar.report(for: day.date, logs: logs, sets: sets, weights: weights))
        }
    }

    private var grid: some View {
        let weekday = ["M", "", "W", "", "F", "", ""]
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: gap) {
                    VStack(spacing: gap) {
                        Color.clear.frame(width: 12, height: 12)
                        ForEach(Array(weekday.enumerated()), id: \.offset) { _, label in
                            Text(label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 12, height: pitch)
                        }
                    }
                    ForEach(columns) { column in
                        VStack(spacing: gap) {
                            Text(column.month ?? "")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(width: pitch, height: 12, alignment: .leading)
                            ForEach(column.days) { day in
                                dayCell(day)
                            }
                        }
                        .id(column.id)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    if let last = columns.last?.id {
                        proxy.scrollTo(last, anchor: .trailing)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: StreakCalendar.Day) -> some View {
        let today = Calendar.current.isDateInToday(day.date)
        return Button {
            Haptics.tap()
            SpotterAnalytics.click("day_cell", screen: "streaks")
            SpotterAnalytics.log("day_report")
            selected = day
        } label: {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(StreakCalendar.color(level: day.level))
                .frame(width: cell, height: cell)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(today ? Color.white : Color.clear, lineWidth: 1)
                }
                .overlay(alignment: .topTrailing) {
                    if day.badge {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 1, y: 0)
                            .offset(x: 3, y: -3)
                    }
                }
                .frame(width: pitch, height: pitch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility(day))
    }

    private func accessibility(_ day: StreakCalendar.Day) -> String {
        let title = day.date.formatted(date: .abbreviated, time: .omitted)
        if day.isFuture { return "\(title), still ahead" }
        if day.points == 0 { return "\(title), no workout" }
        return "\(title), \(day.points) points" + (day.badge ? ", best day in a streak" : "")
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textTertiary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(StreakCalendar.color(level: level))
                    .frame(width: 10, height: 10)
            }
            Text("More").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
            Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.white)
            Text("Best day").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textTertiary)
        }
    }
}

struct DayReportView: View {
    let report: StreakCalendar.Report
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue

    private var weightUnit: Measure.Weight { Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if report.isFuture {
                        empty("This day hasn't happened yet.", "Come back after you train.")
                    } else if report.workouts.isEmpty {
                        empty("No workout logged.", "Squares fill in after a coached session.")
                    } else {
                        stats
                        if report.badge { badgeNote }
                        ForEach(report.exercises) { block in
                            exerciseCard(block)
                        }
                        if let weightKg = report.weightKg {
                            weighIn(weightKg)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(report.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        SpotterAnalytics.click("day_report_done", screen: "day_report")
                        dismiss()
                    }.font(.body.weight(.semibold))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.isFuture ? String(localized: "Ahead") : (report.workouts.isEmpty ? String(localized: "Rest day") : String(localized: "\(report.points) points")))
                .font(.display(32, weight: .heavy))
                .foregroundStyle(.white)
            Text("Points are your reps and holds, weighted by form score.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            tile("\(report.reps)", "reps")
            tile(report.holdSeconds > 0 ? "\(report.holdSeconds)s" : "–", "holds")
            tile("\(max(report.minutes, report.workouts.isEmpty ? 0 : 1))", "min")
            tile(report.form == 0 ? "–" : "\(report.form)", "form")
        }
    }

    private var badgeNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill").foregroundStyle(Theme.accent)
            Text(badgeText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var badgeText: String {
        if report.streakLength >= 2 && report.isAllTimeBest {
            return String(localized: "Best day in this \(report.streakLength)-day streak, and the most points you've scored.")
        }
        if report.streakLength >= 2 {
            return String(localized: "Best day in this \(report.streakLength)-day streak.")
        }
        return String(localized: "Most points you've scored in a day.")
    }

    private func exerciseCard(_ block: StreakCalendar.ExerciseBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(block.name).font(.display(17, weight: .bold)).foregroundStyle(.white)
            ForEach(Array(block.sets.enumerated()), id: \.offset) { _, set in
                HStack {
                    Text("Set \(set.setNumber)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(setLine(set))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            if let fault = topFault(in: block.sets) {
                Text(fault)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.warn)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
    }

    private func setLine(_ set: SetLog) -> String {
        let effort = set.reps > 0
            ? String(localized: "\(set.reps) reps")
            : String(localized: "\(set.holdSeconds)s hold")
        let load = set.weightKg > 0
            ? " · \(Measure.format(weightUnit.fromKilograms(set.weightKg))) \(weightUnit.symbol)"
            : ""
        return "\(effort)\(load) · \(set.avgFormScore)"
    }

    private func topFault(in sets: [SetLog]) -> String? {
        var counts: [String: Int] = [:]
        for set in sets { for fault in set.faults { counts[fault, default: 0] += 1 } }
        return counts.max { $0.value < $1.value }?.key
    }

    private func weighIn(_ kg: Double) -> some View {
        HStack {
            Text("Weigh-in").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("\(Measure.format(weightUnit.fromKilograms(kg))) \(weightUnit.symbol)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
    }

    private func tile(_ value: String, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.display(18, weight: .heavy)).foregroundStyle(.white).monospacedDigit()
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func empty(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.display(18, weight: .bold)).foregroundStyle(.white)
            Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
