import SwiftUI

struct WorkoutSummaryView: View {
    @ObservedObject var session: TrainerSession
    var onDone: () -> Void
    var onUnlockCoaching: () -> Void

    private var results: [SetResult] { session.results }
    private var coachedResults: [SetResult] { results.filter(\.coached) }
    private var totalReps: Int { results.reduce(0) { $0 + $1.reps } }
    private var average: Int {
        guard !coachedResults.isEmpty else { return 0 }
        return coachedResults.reduce(0) { $0 + $1.avgScore } / coachedResults.count
    }
    private var minutes: Int { max(1, Int(Date().timeIntervalSince(session.startedAt) / 60)) }

    private var topFix: (String, Int)? {
        var counts: [String: Int] = [:]
        for r in results { for (k, v) in r.faults { counts[k, default: 0] += v } }
        return counts.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    private var byExercise: [(String, [SetResult])] {
        var order: [String] = []
        var groups: [String: [SetResult]] = [:]
        for r in results {
            if groups[r.exerciseName] == nil { order.append(r.exerciseName) }
            groups[r.exerciseName, default: []].append(r)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workout complete").eyebrow(Theme.accent)
                        Text(session.title).font(.display(32, weight: .heavy)).foregroundStyle(.white)
                    }
                    .padding(.top, 24)

                    HStack(spacing: 10) {
                        stat("\(minutes)", "minutes")
                        stat("\(totalReps)", "reps")
                        stat("\(results.count)", "sets")
                    }

                    if coachedResults.isEmpty {
                        Button {
                            SpotterAnalytics.click("open_paywall", screen: "workout_summary", ["source": "coaching_locked"])
                            onUnlockCoaching()
                        } label: {
                            Card {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Reps counted", systemImage: "checkmark.circle.fill")
                                        .font(.display(17, weight: .bold)).foregroundStyle(.white)
                                    Text("Form scores show up on coached sets. Goal programs are part of Spotter Pro.")
                                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Card {
                            HStack(spacing: 16) {
                                ScoreRing(score: average, size: 84, lineWidth: 8)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Average form score").font(.display(17, weight: .bold)).foregroundStyle(.white)
                                    Text(verdict).font(.subheadline).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }

                    if let fix = topFix {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Your #1 fix for next time", systemImage: "target")
                                    .font(.display(15, weight: .bold)).foregroundStyle(Theme.warn)
                                Text(fix.0).font(.display(20, weight: .bold)).foregroundStyle(.white)
                                Text(fix.1 == 1
                                     ? String(localized: "Spotter flagged this \(fix.1) time today. It'll watch for it next session.")
                                     : String(localized: "Spotter flagged this \(fix.1) times today. It'll watch for it next session."))
                                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Breakdown").eyebrow()
                        ForEach(byExercise, id: \.0) { name, sets in
                            Card(padding: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(name).font(.display(16, weight: .semibold)).foregroundStyle(.white)
                                        Text(sets.map { $0.reps > 0 ? "\($0.reps)" : "\($0.holdSeconds)s" }.joined(separator: " · "))
                                            .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    let scored = sets.filter(\.coached)
                                    if !scored.isEmpty {
                                        ScoreRing(score: scored.reduce(0) { $0 + $1.avgScore } / scored.count, size: 44, lineWidth: 4)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            VStack {
                Spacer()
                Button("Done") {
                    SpotterAnalytics.click("workout_done", screen: "workout_summary")
                    onDone()
                }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private var verdict: String {
        switch average {
        case 90...: return String(localized: "Textbook. Time to add weight or reps.")
        case 75..<90: return String(localized: "Solid session. A few reps to clean up.")
        case 1..<75: return String(localized: "Good effort. Slow down and own every rep.")
        default: return String(localized: "Complete a full set to get a score.")
        }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.display(28, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
