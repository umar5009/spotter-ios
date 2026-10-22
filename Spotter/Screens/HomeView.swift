import SwiftUI
import SwiftData
import Charts

struct HomeView: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var router: AppRouter
    @AppStorage("place") private var placeRaw = TrainingPlace.home.rawValue
    @AppStorage("level") private var levelRaw = Level.beginner.rawValue
    @AppStorage("goal") private var goalRaw = Goal.strength.rawValue
    @Query(sort: \WorkoutLog.date, order: .reverse) private var logs: [WorkoutLog]
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private var goal: Goal { Goal(rawValue: goalRaw) ?? .strength }
    private var place: TrainingPlace { TrainingPlace(rawValue: placeRaw) ?? .home }
    private var level: Level { Level(rawValue: levelRaw) ?? .beginner }

    private var activeDay: Date {
        if weekDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: selectedDay) }) {
            return Calendar.current.startOfDay(for: selectedDay)
        }
        return Calendar.current.startOfDay(for: .now)
    }

    private var plan: WorkoutPlan {
        PlanBuilder.plan(on: activeDay, place: place, level: level, goal: goal, isPro: store.isPro)
    }

    private var weekDates: [Date] {
        let start = PlanBuilder.startOfWeek()
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private var trainedDays: Set<Date> {
        Set(logs.map { Calendar.current.startOfDay(for: $0.date) })
    }

    private var streak: Int { Streak.current(from: logs.map(\.date)) }
    private var bestStreak: Int { Streak.longest(from: logs.map(\.date)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    quoteCard
                    todayCard
                    if !store.isPro { upgradeCard }
                    weekCard
                    quickStart
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                ExerciseDetailView(exerciseID: id)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).eyebrow()
                Text(greeting).font(.display(30, weight: .heavy)).foregroundStyle(.white)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? Theme.warn : Theme.textTertiary)
                Text("\(streak)").font(.display(17, weight: .bold)).monospacedDigit().foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.stroke))
        }
        .padding(.top, 12)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return String(localized: "Good morning")
        case 12..<17: return String(localized: "Good afternoon")
        default: return String(localized: "Good evening")
        }
    }

    private var quoteCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "quote.opening")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's note").eyebrow(Theme.accent)
                Text(DailyQuote.line(goal: goal))
                    .font(.display(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke))
    }

    private var todayCard: some View {
        let plan = self.plan
        let isToday = Calendar.current.isDateInToday(activeDay)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? Theme.warn : Theme.textTertiary)
                Text(streak == 0 ? String(localized: "No streak yet") : String(localized: "\(streak) day streak"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                if bestStreak > 0 {
                    Text(String(localized: "Best \(bestStreak)"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(weekDates, id: \.self) { day in
                        dayChip(day)
                    }
                }
            }
            HStack {
                Text(isToday ? String(localized: "Today's session") : activeDay.formatted(.dateTime.weekday(.wide))).eyebrow(Theme.accent)
                Spacer()
                Pill(text: "\(plan.estimatedMinutes) min", symbol: "clock")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.title).font(.display(28, weight: .heavy)).foregroundStyle(.white)
                Text(plan.focus).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            VStack(spacing: 8) {
                ForEach(plan.items) { item in
                    let spec = ExerciseLibrary.spec(item.exerciseID)
                    HStack(spacing: 12) {
                        Image(systemName: spec.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 36, height: 36)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(spec.name).font(.display(16, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("\(item.sets) × \(item.target)\(spec.kind.isHold ? "s" : "")")
                            .font(.system(size: 15, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if plan.lockedCount > 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(String(localized: "+\(plan.lockedCount) exercises in your full plan"))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                        Spacer()
                    }
                }
            }
            Button {
                SpotterAnalytics.click("start_workout", screen: "today", ["title": plan.title])
                router.start(ActiveWorkout(title: plan.title, plan: plan.items))
            } label: {
                Label(isToday ? String(localized: "Start with AI coach") : String(localized: "Train this day"), systemImage: "camera.viewfinder")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(18)
        .background {
            ZStack {
                Theme.surface
                RadialGradient(colors: [Theme.accent.opacity(0.18), .clear], center: .topTrailing, startRadius: 10, endRadius: 320)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.stroke))
    }

    private func dayChip(_ day: Date) -> some View {
        let cal = Calendar.current
        let selected = cal.isDate(day, inSameDayAs: activeDay)
        let trained = trainedDays.contains(cal.startOfDay(for: day))
        return Button {
            Haptics.tap()
            SpotterAnalytics.click("select_plan_day", screen: "today")
            selectedDay = cal.startOfDay(for: day)
        } label: {
            VStack(spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 11, weight: .bold))
                Text(day.formatted(.dateTime.day()))
                    .font(.display(16, weight: .heavy))
                    .monospacedDigit()
                Circle()
                    .fill(trained ? (selected ? Color.black : Theme.accent) : Color.clear)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(selected ? Color.black.opacity(0.35) : Theme.stroke, lineWidth: 1))
            }
            .foregroundStyle(selected ? Color.black : Color.white)
            .frame(width: 52, height: 74)
            .background(selected ? Theme.accent : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(cal.isDateInToday(day) && !selected ? Theme.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var upgradeCard: some View {
        Button {
            SpotterAnalytics.click("open_paywall", screen: "today", ["source": "upgrade_card"])
            router.showPaywall = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Theme.violet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock your full plan").font(.display(16, weight: .bold)).foregroundStyle(.white)
                    Text("Gym mode, tempo coaching and all 9 exercises").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.violet.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private struct DayScore: Identifiable {
        let id = UUID()
        let label: String
        let score: Int
    }

    private var week: [DayScore] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayLogs = logs.filter { cal.isDate($0.date, inSameDayAs: day) }
            let score = dayLogs.isEmpty ? 0 : dayLogs.reduce(0) { $0 + $1.avgFormScore } / dayLogs.count
            return DayScore(label: day.formatted(.dateTime.weekday(.narrow)), score: score)
        }
    }

    private var weekCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Form score · last 7 days").eyebrow()
                    Spacer()
                    let scored = week.filter { $0.score > 0 }
                    if !scored.isEmpty {
                        Text("\(scored.reduce(0) { $0 + $1.score } / scored.count) avg")
                            .font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                    }
                }
                Chart(week) { day in
                    BarMark(x: .value("Day", day.label), y: .value("Form", max(day.score, 3)))
                        .foregroundStyle(day.score > 0 ? Theme.scoreColor(day.score) : Color.white.opacity(0.1))
                        .cornerRadius(5)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.textTertiary) }
                }
                .frame(height: 110)
            }
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick start").eyebrow()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ExerciseLibrary.all) { spec in
                        NavigationLink(value: spec.id) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: spec.symbol)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                    Spacer()
                                    if !spec.isFree && !store.isPro {
                                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.textTertiary)
                                    }
                                }
                                Spacer()
                                Text(spec.name).font(.display(15, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                                Text(spec.category.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                            }
                            .padding(14)
                            .frame(width: 132, height: 132)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke))
                        }
                        .buttonStyle(.plain)
                        .trackClick("quick_start", screen: "today", ["exercise": spec.id])
                    }
                }
            }
        }
    }
}
