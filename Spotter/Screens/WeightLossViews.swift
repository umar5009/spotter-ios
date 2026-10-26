import SwiftUI
import SwiftData

/// Progress card for the loss target, the badge, and the week or month check-in.
struct WeightLossCard: View {
    @Query(sort: \WeightEntry.date) private var entries: [WeightEntry]
    @AppStorage("goalWeightKg") private var goalWeightKg = 0.0
    @AppStorage(WeightLoss.startKey) private var lossStartKg = 0.0
    @AppStorage(WeightLoss.cadenceKey) private var cadenceRaw = LossCadence.week.rawValue
    @AppStorage(WeightLoss.periodKey) private var lossPeriodKg = 0.0
    @AppStorage(WeightLoss.badgeKey) private var badgeGoalKg = 0.0
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue
    @State private var showLog = false
    @State private var showTarget = false

    private var unit: Measure.Weight { Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms }
    private var cadence: LossCadence { LossCadence(rawValue: cadenceRaw) ?? .week }
    private var status: WeightLoss.Status? {
        WeightLoss.status(entries: entries, goalKg: goalWeightKg, startKg: lossStartKg, cadence: cadence, periodKg: lossPeriodKg)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weight loss").eyebrow(Theme.accent)
                Spacer()
                if badgeGoalKg > 0 {
                    Label("Goal weight", systemImage: "seal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            if let status {
                filled(status)
            } else {
                Text("Set a goal under your current weight. The bar fills as you lose it.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                WeightLossBar(fraction: 0)
                Button("Set target") {
                    SpotterAnalytics.click("open_loss_target", screen: "progress")
                    showTarget = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke))
        .sheet(isPresented: $showLog) { WeightLogSheet() }
        .sheet(isPresented: $showTarget) { WeightLossTargetSheet() }
    }

    private func filled(_ status: WeightLoss.Status) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let current = status.currentKg {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(amount(current)).font(.display(28, weight: .heavy)).foregroundStyle(.white)
                    Text(unit.symbol).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(Int((status.fraction * 100).rounded()))%")
                        .font(.display(17, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
            }
            WeightLossBar(fraction: status.fraction)
            Text(summary(status))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(periodLine(status))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 16) {
                Button("Log weight") {
                    SpotterAnalytics.click("log_weight", screen: "progress")
                    showLog = true
                }
                Button("Edit target") {
                    SpotterAnalytics.click("open_loss_target", screen: "progress")
                    showTarget = true
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.accent)
        }
    }

    private func summary(_ status: WeightLoss.Status) -> String {
        let goal = "\(amount(status.goalKg)) \(unit.symbol)"
        guard status.currentKg != nil else {
            return String(localized: "Goal \(goal). Log a weigh-in to start the bar.")
        }
        if status.startKg - status.goalKg <= 0.05 {
            return String(localized: "Set a goal under \(amount(status.startKg)) \(unit.symbol) to track a loss.")
        }
        if status.reached {
            return String(localized: "Goal reached · \(goal)")
        }
        return String(localized: "\(amount(status.lostKg)) \(unit.symbol) lost · \(amount(status.remainingKg)) \(unit.symbol) to \(goal)")
    }

    private func periodLine(_ status: WeightLoss.Status) -> String {
        let change = WeightTrend.changeLabel(status.periodDelta, unit: unit)
        if status.periodTargetKg > 0 {
            let target = "\(amount(status.periodTargetKg)) \(unit.symbol)"
            return String(localized: "\(status.cadence.periodName) · \(change) · target \(target)")
        }
        return String(localized: "\(status.cadence.periodName) · \(change)")
    }

    private func amount(_ kg: Double) -> String {
        Measure.format(unit.fromKilograms(max(0, kg)))
    }
}

struct WeightLossBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            let width = max(0, min(1, fraction)) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(Theme.accent).frame(width: width)
            }
        }
        .frame(height: 10)
        .accessibilityLabel(Text("Weight loss progress"))
        .accessibilityValue(Text("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent"))
    }
}

struct WeightLossTargetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    @AppStorage("goalWeightKg") private var goalWeightKg = 0.0
    @AppStorage(WeightLoss.startKey) private var lossStartKg = 0.0
    @AppStorage(WeightLoss.cadenceKey) private var cadenceRaw = LossCadence.week.rawValue
    @AppStorage(WeightLoss.periodKey) private var lossPeriodKg = 0.0
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue

    @State private var goalText = ""
    @State private var periodText = ""
    @State private var error: String?

    private var unit: Measure.Weight { Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms }
    private var cadence: LossCadence { LossCadence(rawValue: cadenceRaw) ?? .week }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Goal weight").eyebrow()
                        HStack(alignment: .firstTextBaseline) {
                            TextField(unit.placeholder, text: $goalText)
                                .keyboardType(.decimalPad)
                                .font(.display(42, weight: .heavy))
                                .foregroundStyle(.white)
                            Text(unit.symbol).font(.title3.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Celebrate").eyebrow()
                        Picker("Celebrate", selection: $cadenceRaw) {
                            ForEach(LossCadence.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cadence.targetField).eyebrow()
                        HStack(alignment: .firstTextBaseline) {
                            TextField("Optional", text: $periodText)
                                .keyboardType(.decimalPad)
                                .font(.display(28, weight: .bold))
                                .foregroundStyle(.white)
                            Text(unit.symbol).font(.body.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        }
                        Text("The bar runs from your latest weigh-in to the goal. A loss in the week or month you pick gets a celebration. Reaching the goal earns the Goal weight badge.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if let error {
                        Text(error).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.bad)
                    }
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Loss target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                }
            }
            .onAppear(perform: prefill)
        }
        .presentationDetents([.medium, .large])
    }

    private func prefill() {
        if goalText.isEmpty, goalWeightKg > 0 {
            goalText = Measure.format(unit.fromKilograms(goalWeightKg))
        }
        if periodText.isEmpty, lossPeriodKg > 0 {
            periodText = Measure.format(unit.fromKilograms(lossPeriodKg))
        }
    }

    private func save() {
        guard let shown = Measure.number(goalText), unit.accepts(shown) else {
            error = String(localized: "Enter a goal between \(unit.rangeDescription).")
            return
        }
        let goal = unit.toKilograms(shown)
        if let latest = entries.first, goal >= latest.weightKg - 0.05 {
            error = String(localized: "Set a goal under your current \(Measure.format(unit.fromKilograms(latest.weightKg))) \(unit.symbol).")
            return
        }

        var period = 0.0
        if !periodText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let shownPeriod = Measure.number(periodText) else {
                error = String(localized: "Enter how much to lose, or leave it blank.")
                return
            }
            period = unit.toKilograms(shownPeriod)
            guard period > 0, period <= 20 else {
                error = String(localized: "Enter a loss up to 20 \(unit.symbol), or leave it blank.")
                return
            }
        }

        let changed = abs(goal - goalWeightKg) > 0.05
        if let latest = entries.first {
            lossStartKg = WeightLoss.rememberStart(latest.weightKg, replacing: lossStartKg, goalChanged: changed)
        }
        goalWeightKg = goal
        lossPeriodKg = period
        SpotterAnalytics.click("set_loss_target", screen: "progress", ["cadence": cadenceRaw])
        Haptics.success()
        dismiss()
    }
}

/// Full-screen celebration. Confetti for a weekly or monthly loss, and a badge at the goal.
struct LossCelebrationLayer: View {
    @Query(sort: \WeightEntry.date) private var entries: [WeightEntry]
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("goalWeightKg") private var goalWeightKg = 0.0
    @AppStorage(WeightLoss.startKey) private var lossStartKg = 0.0
    @AppStorage(WeightLoss.cadenceKey) private var cadenceRaw = LossCadence.week.rawValue
    @AppStorage(WeightLoss.periodKey) private var lossPeriodKg = 0.0
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue
    @State private var celebration: WeightLoss.Celebration?

    private var unit: Measure.Weight { Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms }
    private var signature: String {
        let latest = entries.last?.weightKg ?? 0
        return "\(entries.count)|\(latest)|\(goalWeightKg)|\(lossStartKg)|\(cadenceRaw)|\(lossPeriodKg)"
    }

    var body: some View {
        ZStack {
            if let celebration {
                Color.black.opacity(0.55).ignoresSafeArea()
                ConfettiBurst()
                card(celebration)
                    .padding(24)
            }
        }
        .onAppear { claim() }
        .onChange(of: signature) { _, _ in claim() }
        .onChange(of: celebration?.id) { _, id in
            if id != nil { Haptics.success() }
        }
        .allowsHitTesting(celebration != nil)
    }

    private func claim() {
        guard onboarded, celebration == nil else { return }
        let cadence = LossCadence(rawValue: cadenceRaw) ?? .week
        celebration = WeightLoss.claim(
            entries: entries,
            goalKg: goalWeightKg,
            startKg: lossStartKg,
            cadence: cadence,
            periodKg: lossPeriodKg
        )
    }

    private func card(_ celebration: WeightLoss.Celebration) -> some View {
        VStack(spacing: 14) {
            switch celebration {
            case .badge(let goalKg):
                Image(systemName: "seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                Text("New badge").eyebrow(Theme.accent)
                Text("Goal weight").font(.display(28, weight: .heavy)).foregroundStyle(.white)
                Text("You reached \(Measure.format(unit.fromKilograms(goalKg))) \(unit.symbol). The badge stays on your home screen.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
            case .period(let cadence, let lostKg, let hitTarget):
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                Text(cadence == .week ? "Down this week" : "Down this month")
                    .font(.display(28, weight: .heavy))
                    .foregroundStyle(.white)
                Text(periodBody(lostKg: lostKg, hitTarget: hitTarget, cadence: cadence))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
            }
            Button("Nice") {
                SpotterAnalytics.click("dismiss_loss_celebration", screen: "today")
                self.celebration = nil
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 6)
        }
        .padding(22)
        .frame(maxWidth: 420)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.stroke))
    }

    private func periodBody(lostKg: Double, hitTarget: Bool, cadence: LossCadence) -> String {
        let amount = "\(Measure.format(unit.fromKilograms(lostKg))) \(unit.symbol)"
        if hitTarget {
            return cadence == .week
                ? String(localized: "\(amount) lost. That hits this week's target.")
                : String(localized: "\(amount) lost. That hits this month's target.")
        }
        return String(localized: "\(amount) lost. Keep the bar moving.")
    }
}

struct ConfettiBurst: View {
    private let start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                for index in 0..<72 {
                    let spin = unit(index, 1)
                    let origin = unit(index, 2)
                    let speed = 140 + unit(index, 3) * 260
                    let sway = sin(elapsed * (1.4 + spin) + Double(index)) * 18
                    let travel = elapsed * speed + origin * size.height
                    let y = travel.truncatingRemainder(dividingBy: size.height + 48) - 40
                    let x = origin * size.width + sway
                    let rect = CGRect(x: x, y: y, width: 7 + unit(index, 4) * 6, height: 12)
                    var piece = context
                    piece.translateBy(x: rect.midX, y: rect.midY)
                    piece.rotate(by: .degrees(elapsed * 180 * (spin > 0.5 ? 1 : -1) + Double(index * 11)))
                    let path = Path(roundedRect: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height), cornerRadius: 2)
                    piece.fill(path, with: .color(color(index)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func color(_ index: Int) -> Color {
        let colors = [Theme.accent, Theme.warn, Theme.violet, Color.white]
        return colors[index % colors.count]
    }

    private func unit(_ index: Int, _ salt: Int) -> Double {
        let raw = sin(Double(index * 127 + salt * 31)) * 43758.5453
        return raw - floor(raw)
    }
}
