import Foundation
import UserNotifications

/// Local reminders for the next two weeks. Each one names that day's exercises.
@MainActor
enum DayReminder {
    static let hourKey = "dayReminderHour"
    static let minuteKey = "dayReminderMinute"
    private static let idPrefix = "spotter.day."

    static func reschedule() async {
        let isPro = UserDefaults.standard.bool(forKey: "cachedIsPro")
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard UserDefaults.standard.bool(forKey: "pushEnabled") else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        let calendar = Calendar.current
        let hour = UserDefaults.standard.object(forKey: hourKey) as? Int ?? 8
        let minute = UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 0
        let place = TrainingPlace(rawValue: UserDefaults.standard.string(forKey: "place") ?? "") ?? .home
        let level = Level(rawValue: UserDefaults.standard.string(forKey: "level") ?? "") ?? .beginner
        let goal = Goal(rawValue: UserDefaults.standard.string(forKey: "goal") ?? "") ?? .strength
        let split = UserDefaults.standard.string(forKey: WeekSplit.storageKey) ?? ""
        let start = calendar.startOfDay(for: .now)

        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            var parts = calendar.dateComponents([.year, .month, .day], from: day)
            parts.hour = hour
            parts.minute = minute
            guard let fire = calendar.date(from: parts), fire > Date() else { continue }

            let workout = session(on: day, place: place, level: level, goal: goal, isPro: isPro, split: split)
            let names = workout.plan.items.map { ExerciseLibrary.spec($0.exerciseID).name }
            let note = DailyQuote.note(goal: goal, title: workout.plan.title, names: names, focus: workout.focus, date: day, calendar: calendar)

            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.sound = .default
            content.userInfo = ["screen": "today"]

            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let id = idPrefix + Self.stamp(day, calendar: calendar)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    private static func session(
        on day: Date,
        place: TrainingPlace,
        level: Level,
        goal: Goal,
        isPro: Bool,
        split: String
    ) -> (plan: WorkoutPlan, focus: TrainingFocus?) {
        let scheduled = PlanBuilder.plan(on: day, place: place, level: level, goal: goal, isPro: isPro, split: split)
        let focus = WeekSplit.focus(weekday: PlanBuilder.mondayIndex(day), in: split)
        let plan = focus == nil
            ? PlanBuilder.applying(DayPlanEdit.ids(on: day), onto: scheduled, level: level, goal: goal, isPro: isPro)
            : scheduled
        return (plan, focus)
    }

    private static func stamp(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
