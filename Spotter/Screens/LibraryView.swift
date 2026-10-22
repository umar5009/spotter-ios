import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: StoreManager
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", home = "Home", gym = "Gym"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .home: return String(localized: "Home")
            case .gym: return String(localized: "Gym")
            }
        }
    }

    private var items: [ExerciseSpec] {
        switch filter {
        case .all: return ExerciseLibrary.all
        case .home: return ExerciseLibrary.all.filter { $0.category == .home }
        case .gym: return ExerciseLibrary.all.filter { $0.category == .gym }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: filter) { _, new in
                        SpotterAnalytics.click("exercise_filter", screen: "exercises", ["filter": new.rawValue])
                    }

                    ForEach(items) { spec in
                        NavigationLink(value: spec.id) {
                            ExerciseRow(spec: spec, locked: !spec.isFree && !store.isPro)
                        }
                        .buttonStyle(.plain)
                        .trackClick("exercise_open", screen: "exercises", ["exercise": spec.id])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                ExerciseDetailView(exerciseID: id)
            }
        }
    }
}

struct ExerciseRow: View {
    let spec: ExerciseSpec
    let locked: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: spec.symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 60, height: 60)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(spec.name).font(.display(17, weight: .bold)).foregroundStyle(.white)
                    if locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.textTertiary) }
                }
                Text(spec.muscles.joined(separator: " · ")).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(1)
                HStack(spacing: 6) {
                    Pill(text: spec.category.title, symbol: spec.category == .gym ? "dumbbell.fill" : "house.fill")
                    Pill(text: spec.camera.label, symbol: "camera.fill")
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke))
    }
}

struct ExerciseDetailView: View {
    let exerciseID: String
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var router: AppRouter
    @AppStorage("level") private var levelRaw = Level.beginner.rawValue
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue
    @State private var sets = 3
    @State private var target = 10
    @State private var weight: Double = 0
    @State private var rest = 60
    @State private var configured = false

    private var spec: ExerciseSpec { ExerciseLibrary.spec(exerciseID) }
    private var weightUnit: Measure.Weight { Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms }
    private var locked: Bool { !spec.isFree && !store.isPro }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(spec.camera.label, systemImage: "camera.viewfinder")
                            .font(.display(16, weight: .bold)).foregroundStyle(Theme.accent)
                        Text(spec.camera.instruction).foregroundStyle(Theme.textSecondary)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What your AI coach watches").eyebrow()
                        checkRow("number", spec.countingDescription)
                        ForEach(spec.rules) { rule in checkRow("exclamationmark.triangle", String(localized: "“\(rule.cue)”")) }
                        if spec.tempoCheck { checkRow("timer", String(localized: "Flags rushed lowering. Slow eccentrics build more muscle.")) }
                        checkRow("waveform", String(localized: "Talks you through every rep, so you never need to look at your phone."))
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to do it").eyebrow()
                        ForEach(Array(spec.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)")
                                    .font(.display(14, weight: .heavy)).foregroundStyle(.black)
                                    .frame(width: 24, height: 24)
                                    .background(Theme.accent, in: Circle())
                                Text(step).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let note = spec.note {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Theme.violet)
                        Text(note).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(14)
                    .background(Theme.violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Card {
                    VStack(spacing: 4) {
                        stepperRow("Sets", control: "sets", value: "\(sets)", minus: { sets = max(1, sets - 1) }, plus: { sets = min(8, sets + 1) })
                        Divider().overlay(Theme.stroke)
                        if spec.kind.isHold {
                            stepperRow("Seconds", control: "seconds", value: "\(target)",
                                       minus: { target = max(10, target - 5) },
                                       plus: { target = min(300, target + 5) })
                        } else {
                            stepperRow("Reps", control: "reps", value: "\(target)",
                                       minus: { target = max(1, target - 1) },
                                       plus: { target = min(50, target + 1) })
                        }
                        Divider().overlay(Theme.stroke)
                        stepperRow("Rest", control: "rest", value: String(localized: "\(rest)s"), minus: { rest = max(15, rest - 15) }, plus: { rest = min(300, rest + 15) })
                        if spec.category == .gym {
                            Divider().overlay(Theme.stroke)
                            stepperRow("Weight", control: "weight", value: weight == 0 ? "–" : "\(Measure.format(weightUnit.fromKilograms(weight))) \(weightUnit.symbol)",
                                       minus: { weight = max(0, weight - weightUnit.toKilograms(weightUnit.step)) },
                                       plus: { weight += weightUnit.toKilograms(weightUnit.step) })
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(spec.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                if locked {
                    SpotterAnalytics.click("open_paywall", screen: "exercise", ["source": "locked_start", "exercise": spec.id])
                    router.showPaywall = true
                } else {
                    SpotterAnalytics.click("start_workout", screen: "exercise", ["exercise": spec.id])
                    let item = PlannedExercise(exerciseID: spec.id, sets: sets, target: target, restSeconds: rest,
                                               weightKg: spec.category == .gym ? weight : nil)
                    router.start(ActiveWorkout(title: spec.name, plan: [item]))
                }
            } label: {
                Label(locked ? "Unlock with Spotter Pro" : "Start with AI coach",
                      systemImage: locked ? "lock.open.fill" : "camera.viewfinder")
            }
            .buttonStyle(PrimaryButtonStyle(color: locked ? Theme.violet : Theme.accent))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.bg.opacity(0.95))
        }
        .onAppear {
            guard !configured else { return }
            configured = true
            let level = Level(rawValue: levelRaw) ?? .beginner
            let planned = PlanBuilder.make(spec.id, level: level, rest: 60)
            sets = planned.sets
            target = planned.target
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: spec.symbol)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(
                    RadialGradient(colors: [Theme.accent.opacity(0.25), Theme.surface], center: .center, startRadius: 4, endRadius: 200),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                )
            Text(spec.equipment).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(spec.muscles, id: \.self) { Pill(text: $0, color: .white) }
                }
            }
        }
        .padding(.top, 8)
    }

    private func checkRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 20)
            Text(text).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepperRow(_ title: LocalizedStringKey, control: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.display(16, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            HStack(spacing: 14) {
                Button {
                    SpotterAnalytics.click("exercise_adjust", screen: "exercise", ["control": control, "direction": "decrease"])
                    minus(); Haptics.tap()
                } label: {
                    Image(systemName: "minus").frame(width: 34, height: 34).background(Color.white.opacity(0.08), in: Circle())
                }
                Text(value).font(.display(17, weight: .bold)).monospacedDigit().foregroundStyle(.white).frame(minWidth: 64)
                Button {
                    SpotterAnalytics.click("exercise_adjust", screen: "exercise", ["control": control, "direction": "increase"])
                    plus(); Haptics.tap()
                } label: {
                    Image(systemName: "plus").frame(width: 34, height: 34).background(Color.white.opacity(0.08), in: Circle())
                }
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}
