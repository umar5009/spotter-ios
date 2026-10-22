import Foundation
import SwiftData

@Model
final class WorkoutLog {
    var id: UUID
    var date: Date
    var title: String
    var durationSeconds: Int
    var totalReps: Int
    var avgFormScore: Int
    var setCount: Int

    init(id: UUID, date: Date, title: String, durationSeconds: Int, totalReps: Int, avgFormScore: Int, setCount: Int) {
        self.id = id
        self.date = date
        self.title = title
        self.durationSeconds = durationSeconds
        self.totalReps = totalReps
        self.avgFormScore = avgFormScore
        self.setCount = setCount
    }
}

@Model
final class SetLog {
    var date: Date
    var sessionID: UUID
    var exerciseID: String
    var exerciseName: String
    var setNumber: Int
    var reps: Int
    var holdSeconds: Int
    var avgFormScore: Int
    var weightKg: Double
    /// One entry per occurrence of a form fault (cue text).
    var faults: [String]

    init(date: Date, sessionID: UUID, exerciseID: String, exerciseName: String, setNumber: Int,
         reps: Int, holdSeconds: Int, avgFormScore: Int, weightKg: Double, faults: [String]) {
        self.date = date
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.avgFormScore = avgFormScore
        self.weightKg = weightKg
        self.faults = faults
    }
}

enum Streak {
    /// Consecutive days with a workout, ending today or yesterday.
    static func current(from dates: [Date], calendar: Calendar = .current) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Longest run of consecutive training days in the log.
    static func longest(from dates: [Date], calendar: Calendar = .current) -> Int {
        let days = Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted()
        guard var previous = days.first else { return 0 }
        var best = 1
        var run = 1
        for day in days.dropFirst() {
            if let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: day) {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
            previous = day
        }
        return best
    }
}
