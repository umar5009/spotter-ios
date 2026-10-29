import SwiftUI

/// The badge in progress, or the latest one earned, centered above a link to the full ladder.
struct BadgeBoardView: View {
    let logs: [WorkoutLog]
    let weights: [WeightEntry]

    @AppStorage("goalWeightKg") private var goalWeightKg = 0.0
    @AppStorage(WeightLoss.startKey) private var lossStartKg = 0.0
    @AppStorage(WeightLoss.cadenceKey) private var cadenceRaw = LossCadence.week.rawValue
    @AppStorage(WeightLoss.periodKey) private var lossPeriodKg = 0.0

    private var report: BadgeReport { makeReport(logs: logs, weights: weights, goalKg: goalWeightKg, startKg: lossStartKg, cadenceRaw: cadenceRaw, periodKg: lossPeriodKg) }

    var body: some View {
        let report = self.report
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                if let current = report.current {
                    badgeMark(current.symbol, earned: true, size: 96)
                    Text(current.title)
                        .font(.display(28, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Earned")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                } else if let next = report.next {
                    badgeMark(next.badge.symbol, earned: false, size: 88)
                    Text(next.badge.title)
                        .font(.display(26, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(next.badge.requirement)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    WeightLossBar(fraction: next.fraction)
                        .frame(maxWidth: 220)
                    Text(next.progress)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            NavigationLink {
                AllBadgesView(logs: logs, weights: weights)
            } label: {
                Text("See all badges")
            }
            .buttonStyle(GlassButtonStyle())
            .trackClick("open_badges", screen: "progress")
        }
    }

    private func badgeMark(_ symbol: String, earned: Bool, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(earned ? Color.black : Theme.accent)
            .frame(width: size, height: size)
            .background(earned ? Theme.accent : Theme.accentSoft, in: Circle())
    }
}

/// Every badge in earn order, with the requirement and how close the log is.
struct AllBadgesView: View {
    let logs: [WorkoutLog]
    let weights: [WeightEntry]

    @AppStorage("goalWeightKg") private var goalWeightKg = 0.0
    @AppStorage(WeightLoss.startKey) private var lossStartKg = 0.0
    @AppStorage(WeightLoss.cadenceKey) private var cadenceRaw = LossCadence.week.rawValue
    @AppStorage(WeightLoss.periodKey) private var lossPeriodKg = 0.0
    @State private var showTarget = false

    private var report: BadgeReport { makeReport(logs: logs, weights: weights, goalKg: goalWeightKg, startKg: lossStartKg, cadenceRaw: cadenceRaw, periodKg: lossPeriodKg) }

    var body: some View {
        let report = self.report
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Earn them in order. A badge stays once you qualify, even if a streak breaks.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                ForEach(Array(report.standings.enumerated()), id: \.element.id) { index, standing in
                    badgeRow(index: index, standing: standing, isNext: report.next?.badge == standing.badge)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTarget) { WeightLossTargetSheet() }
    }

    private func badgeRow(index: Int, standing: BadgeStanding, isNext: Bool) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(standing.earned ? Color.black : .white)
                    .frame(width: 28, height: 28)
                    .background(standing.earned ? Theme.accent : Color.white.opacity(0.08), in: Circle())

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: standing.badge.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(standing.earned ? Theme.accent : Theme.textSecondary)
                        Text(standing.badge.title)
                            .font(.display(17, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        if standing.earned {
                            Text("Earned")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.accent)
                        } else if isNext {
                            Text("Up next")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.warn)
                        }
                    }
                    Text(standing.badge.requirement)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !standing.earned {
                        WeightLossBar(fraction: standing.fraction)
                        Text(standing.progress)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if standing.badge == .goalWeight && !standing.earned && goalWeightKg <= 0 {
                        Button("Set a loss target") {
                            SpotterAnalytics.click("open_loss_target", screen: "badges")
                            showTarget = true
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(index + 1). \(standing.badge.title). \(standing.badge.requirement). \(standing.progress)"))
    }
}

private func makeReport(
    logs: [WorkoutLog],
    weights: [WeightEntry],
    goalKg: Double,
    startKg: Double,
    cadenceRaw: String,
    periodKg: Double
) -> BadgeReport {
    let cadence = LossCadence(rawValue: cadenceRaw) ?? .week
    return BadgeBoard.report(
        logs: logs,
        weights: weights,
        goalKg: goalKg,
        startKg: startKg,
        cadence: cadence,
        periodKg: periodKg
    )
}
