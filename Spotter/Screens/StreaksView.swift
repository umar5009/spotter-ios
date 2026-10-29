import SwiftData
import SwiftUI

/// The streak calendar, with the highest-scoring days listed underneath.
struct StreaksView: View {
    @Query(sort: \WorkoutLog.date) private var logs: [WorkoutLog]
    @Query(sort: \SetLog.date) private var sets: [SetLog]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @State private var selected: StreakCalendar.Day?

    private var days: [StreakCalendar.Day] { StreakCalendar.rankedDays(logs: logs, sets: sets) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StreakCalendarCard(logs: logs, sets: sets, weights: weights)
            bestDays
        }
        .sheet(item: $selected) { day in
            DayReportView(report: StreakCalendar.report(for: day.date, logs: logs, sets: sets, weights: weights))
        }
    }

    private var bestDays: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Best days").eyebrow()
            if days.isEmpty {
                Text("Squares fill in after a coached session.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke))
            } else {
                VStack(spacing: 8) {
                    ForEach(days) { day in
                        Button {
                            Haptics.tap()
                            SpotterAnalytics.click("best_day", screen: "streaks")
                            SpotterAnalytics.log("day_report")
                            selected = day
                        } label: {
                            dayRow(day)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func dayRow(_ day: StreakCalendar.Day) -> some View {
        let average = form(on: day.date)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(StreakCalendar.color(level: day.level))
                .frame(width: 14, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.display(16, weight: .bold))
                    .foregroundStyle(.white)
                if average > 0 {
                    Text(String(localized: "\(average) avg"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 8)
            if day.badge {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            Text(String(localized: "\(day.points) points"))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
    }

    private func form(on date: Date) -> Int {
        let samples = logs.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.map(\.avgFormScore).filter { $0 > 0 }
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / samples.count
    }
}
