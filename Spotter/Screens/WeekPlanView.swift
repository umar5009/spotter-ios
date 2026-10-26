import SwiftUI

/// Assigns a repeating focus to each weekday: chest, back, legs, and the rest.
struct WeekPlanView: View {
    var onOpenDay: ((Date) -> Void)? = nil

    @ObservedObject private var weekSplit = WeekSplitStore.shared
    @AppStorage("place") private var placeRaw = TrainingPlace.home.rawValue
    @Environment(\.dismiss) private var dismiss

    private var place: TrainingPlace { TrainingPlace(rawValue: placeRaw) ?? .home }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Each choice repeats every week. Tap a day to open it on the home screen.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(0..<7, id: \.self) { index in
                        dayRow(index)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Training week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func dayRow(_ index: Int) -> some View {
        let focus = weekSplit.focus(weekday: index)
        return HStack(spacing: 12) {
            Button {
                open(index)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: focus?.symbol ?? "calendar")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 36, height: 36)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WeekSplit.weekdayName(index))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.textTertiary)
                        Text(focus?.dayName ?? String(localized: "Spotter's plan"))
                            .font(.display(17, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(exerciseLine(focus))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Menu {
                Button("Spotter's plan") { choose(nil, weekday: index) }
                Divider()
                ForEach(TrainingFocus.allCases) { option in
                    Button(option.dayName, systemImage: option.symbol) { choose(option, weekday: index) }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
        .accessibilityLabel(Text("\(WeekSplit.weekdayName(index)), \(focus?.dayName ?? String(localized: "Spotter's plan"))"))
    }

    private func exerciseLine(_ focus: TrainingFocus?) -> String {
        guard let focus else { return String(localized: "Automatic exercises") }
        return focus.exerciseIDs(place: place)
            .map { ExerciseLibrary.spec($0).name }
            .joined(separator: " · ")
    }

    private func open(_ index: Int) {
        let start = PlanBuilder.startOfWeek()
        guard let day = Calendar.current.date(byAdding: .day, value: index, to: start) else { return }
        SpotterAnalytics.click("open_weekday", screen: "week_plan", ["day": "\(index)"])
        onOpenDay?(day)
        dismiss()
    }

    private func choose(_ focus: TrainingFocus?, weekday index: Int) {
        SpotterAnalytics.click("set_weekday_focus", screen: "week_plan", ["day": "\(index)", "focus": focus?.rawValue ?? "automatic"])
        weekSplit.set(focus, weekday: index)
        let start = PlanBuilder.startOfWeek()
        if let day = Calendar.current.date(byAdding: .day, value: index, to: start) {
            DayPlanEdit.clear(on: day)
            onOpenDay?(day)
        }
    }
}
