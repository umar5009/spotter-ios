import Foundation

/// A short note that changes once per calendar day, picked from the user's goal.
enum DailyQuote {
    static func line(goal: Goal, date: Date = .now, calendar: Calendar = .current) -> String {
        let pool = quotes(for: goal)
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        return pool[(day - 1) % pool.count]
    }

    private static func quotes(for goal: Goal) -> [String] {
        switch goal {
        case .fatLoss:
            return [
                String(localized: "Fat loss is a weekly trend, not a number you punish yourself with each morning."),
                String(localized: "Finish the session. The scale follows the weeks you don't skip."),
                String(localized: "A smaller deficit you can keep beats a perfect diet you quit on Thursday."),
                String(localized: "Train hard enough to sweat. Eat enough to come back tomorrow."),
                String(localized: "The streak is doing more for your weight than one brutal workout."),
                String(localized: "Log the weigh-in and get on with the day. One reading is not a verdict."),
                String(localized: "Walk into today's session like the result is already decided by showing up."),
                String(localized: "You don't have to feel motivated. You have to do the next set."),
                String(localized: "Keep the reps honest. Sloppy volume doesn't move the trend."),
                String(localized: "This month is a stack of ordinary days. Today is one of them.")
            ]
        case .strength:
            return [
                String(localized: "Add a little, keep the form. That is the whole sport."),
                String(localized: "A clean rep you can repeat is stronger than a heavy one you survive."),
                String(localized: "The set counts when the last rep looks like the first."),
                String(localized: "Leave one rep in the tank, not the whole workout."),
                String(localized: "Strength is borrowed from the sessions you finish on ordinary days."),
                String(localized: "Slow the lowering. That's where today's progress hides."),
                String(localized: "Don't chase a number that makes the next session worse."),
                String(localized: "Brace, then move. The weight only goes up if the position holds."),
                String(localized: "Show up sore and do the work you can do well."),
                String(localized: "Your best lift is the one you can film and be proud of.")
            ]
        case .mobility:
            return [
                String(localized: "Range you can control is range you get to keep."),
                String(localized: "Move slowly enough to feel the position, then own it."),
                String(localized: "Pain is a stop sign. Discomfort at the end range is the work."),
                String(localized: "A shorter session with full range beats rushing through half of it."),
                String(localized: "Breathe out as you reach the hard part. Don't hold the air hostage."),
                String(localized: "Today's job is to leave the joint moving better than you found it."),
                String(localized: "Smooth reps are the point. Speed can wait."),
                String(localized: "If the form breaks, the set is over. That's discipline, not quitting."),
                String(localized: "Come back tomorrow. Mobility is a practice, not a test."),
                String(localized: "Stand taller when you finish than when you started.")
            ]
        case .consistency:
            return [
                String(localized: "The streak is the goal. Everything else follows from not breaking it."),
                String(localized: "Ten minutes done beats an hour you keep rescheduling."),
                String(localized: "You don't need a perfect week. You need today."),
                String(localized: "Same effort, ordinary day. That's how a habit gets boring enough to last."),
                String(localized: "Missing once is a date on a calendar. Missing twice is a story you start telling."),
                String(localized: "Start the session before you negotiate with yourself."),
                String(localized: "Future you only gets the workouts you actually do."),
                String(localized: "A short recovery day still counts. Zero does not."),
                String(localized: "Don't add a new plan. Finish this one."),
                String(localized: "Show up like someone is counting. The streak is.")
            ]
        }
    }
}
