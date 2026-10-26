import SwiftUI

/// Current rank, the next badge, and every badge the log can award.
struct BadgeBoardView: View {
    let logs: [WorkoutLog]
    let weights: [WeightEntry]
    var onSetTarget: () -> Void

    @AppStorage("goalWeightKg") private var goalWeightKg = 0.0
    @AppStorage(WeightLoss.startKey) private var lossStartKg = 0.0
    @AppStorage(WeightLoss.cadenceKey) private var cadenceRaw = LossCadence.week.rawValue
    @AppStorage(WeightLoss.periodKey) private var lossPeriodKg = 0.0

    private var report: BadgeReport {
        let cadence = LossCadence(rawValue: cadenceRaw) ?? .week
        return BadgeBoard.report(
            logs: logs,
            weights: weights,
            goalKg: goalWeightKg,
            startKg: lossStartKg,
            cadence: cadence,
            periodKg: lossPeriodKg
        )
    }

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        let report = self.report
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Badges").eyebrow(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.current?.title ?? String(localized: "No badge yet"))
                        .font(.display(24, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(report.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let next = report.next {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Next · \(next.badge.title)"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        WeightLossBar(fraction: next.fraction)
                        Text(next.progress)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(report.standings) { standing in
                        cell(standing)
                    }
                }
            }
        }
    }

    private func cell(_ standing: BadgeStanding) -> some View {
        let lockedGoal = standing.badge == .goalWeight && !standing.earned && goalWeightKg <= 0
        return Button {
            guard lockedGoal else { return }
            SpotterAnalytics.click("open_loss_target", screen: "progress", ["source": "badge"])
            onSetTarget()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: standing.badge.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(standing.earned ? Theme.accent : Theme.textTertiary)
                Text(standing.badge.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(standing.earned ? .white : Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .padding(.horizontal, 6)
            .background(standing.earned ? Theme.accentSoft : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(standing.earned ? Theme.accent.opacity(0.45) : Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(standing.badge.title), \(standing.progress)"))
    }
}
