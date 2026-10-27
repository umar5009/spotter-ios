import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var router: AppRouter
    @AppStorage("freeCoachingIDs") private var freeCoachingRaw = ""
    @AppStorage("level") private var levelRaw = Level.beginner.rawValue
    @State private var browse: Browse = .all
    @State private var showWeekPlan = false

    enum Browse: Hashable {
        case all, free
        case program(ExerciseProgram)

        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .free: return String(localized: "Free")
            case .program(let program): return program.title
            }
        }
    }

    private var chips: [Browse] {
        [.all, .free] + ExerciseProgram.allCases.map { .program($0) }
    }

    private var items: [ExerciseSpec] {
        switch browse {
        case .all: return ExerciseLibrary.all
        case .free: return ExerciseLibrary.free
        case .program(let program): return ExerciseLibrary.listed(in: program)
        }
    }

    private var level: Level { Level(rawValue: levelRaw) ?? .beginner }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekCard
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chips, id: \.title) { chip in
                                let selected = browse == chip
                                Button {
                                    SpotterAnalytics.click("exercise_filter", screen: "exercises", ["filter": chip.title])
                                    browse = chip
                                } label: {
                                    Text(chip.title)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(selected ? Color.black : Color.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selected ? Theme.accent : Color.white.opacity(0.06), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if case .program(let program) = browse {
                        programBanner(program)
                    }

                    ForEach(items) { spec in
                        NavigationLink(value: spec.id) {
                            ExerciseRow(spec: spec, locked: !spec.isFree && !store.isPro, freeCoach: !store.isPro && freeCoachingRaw.split(separator: ",").contains(Substring(spec.id)))
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
            .navigationDestination(for: ExerciseProgram.self) { program in
                ProgramDetailView(program: program)
            }
            .sheet(isPresented: $showWeekPlan) {
                WeekPlanView()
            }
        }
    }

    private var weekCard: some View {
        Button {
            SpotterAnalytics.click("open_week_plan", screen: "exercises")
            showWeekPlan = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training week").font(.display(16, weight: .bold)).foregroundStyle(.white)
                    Text("Set chest, back, legs, and the other days").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke))
        }
        .buttonStyle(.plain)
    }

    private func programBanner(_ program: ExerciseProgram) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(program.subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Button {
                if store.isPro {
                    let plan = ProgramSession.plan(for: program, level: level)
                    guard !plan.isEmpty else { return }
                    SpotterAnalytics.click("start_workout", screen: "exercises", ["program": program.rawValue])
                    router.start(ActiveWorkout(title: program.title, plan: plan))
                } else {
                    SpotterAnalytics.click("open_paywall", screen: "exercises", ["source": "program", "program": program.rawValue])
                    router.showPaywall = true
                }
            } label: {
                Label(store.isPro ? "Start program" : "Unlock with Spotter Pro", systemImage: store.isPro ? "play.fill" : "lock.open.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: store.isPro ? Theme.accent : Theme.violet))
        }
        .padding(16)
        .background(Theme.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.violet.opacity(0.35)))
    }
}

struct ExerciseRow: View {
    let spec: ExerciseSpec
    let locked: Bool
    var freeCoach: Bool = false

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
                    if let program = spec.programs.first {
                        Pill(text: program.title, symbol: program.symbol, color: Theme.violet)
                    } else {
                        Pill(text: spec.category.title, symbol: spec.category == .gym ? "dumbbell.fill" : "house.fill")
                    }
                    if freeCoach {
                        Pill(text: String(localized: "Free coach"), symbol: "waveform", color: Theme.accent)
                    }
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
    @AppStorage("freeCoachingIDs") private var freeCoachingRaw = ""

    private var spec: ExerciseSpec { ExerciseLibrary.spec(exerciseID) }
    private var weightUnit: Measure.Weight { Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms }
    private var locked: Bool { !spec.isFree && !store.isPro }
    private var coachingOn: Bool {
        _ = freeCoachingRaw
        return store.isPro || FreeCoaching.includes(spec.id)
    }

    private var startTitle: String {
        if locked { return String(localized: "Unlock with Spotter Pro") }
        if coachingOn { return String(localized: "Start with AI coach") }
        return String(localized: "Start workout")
    }

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
                if !locked && !coachingOn {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Reps are free", systemImage: "checkmark.circle.fill")
                                .font(.display(16, weight: .bold)).foregroundStyle(.white)
                            Text("Live form coaching is free on the two exercises you picked. This one counts your reps without corrections.")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
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
                                       minus: { weight = LiftLoad.stepped(weight, direction: -1, unit: weightUnit) },
                                       plus: { weight = LiftLoad.stepped(weight, direction: 1, unit: weightUnit) })
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
            VStack(spacing: 8) {
                if !locked && !coachingOn {
                    Button {
                        SpotterAnalytics.click("open_paywall", screen: "exercise", ["source": "coaching_locked", "exercise": spec.id])
                        router.showPaywall = true
                    } label: {
                        Text("Unlock live coaching")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
                Button {
                    if locked {
                        SpotterAnalytics.click("open_paywall", screen: "exercise", ["source": "locked_start", "exercise": spec.id])
                        router.showPaywall = true
                    } else {
                        SpotterAnalytics.click("start_workout", screen: "exercise", ["exercise": spec.id, "coaching": coachingOn ? "true" : "false"])
                        let item = PlannedExercise(exerciseID: spec.id, sets: sets, target: target, restSeconds: rest,
                                                   weightKg: spec.category == .gym ? weight : nil)
                        router.start(ActiveWorkout(title: spec.name, plan: [item]))
                    }
                } label: {
                    Label(startTitle, systemImage: locked ? "lock.open.fill" : "camera.viewfinder")
                }
                .buttonStyle(PrimaryButtonStyle(color: locked ? Theme.violet : Theme.accent))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.bg.opacity(0.95))
        }
        .onAppear {
            guard !configured else { return }
            let level = Level(rawValue: levelRaw) ?? .beginner
            let planned = PlanBuilder.make(spec.id, level: level, rest: 60)
            sets = planned.sets
            target = planned.target
            if spec.category == .gym {
                weight = LiftLoad.kilograms(for: spec.id)
            }
            configured = true
        }
        .onChange(of: weight) { _, new in
            guard configured, spec.category == .gym else { return }
            LiftLoad.save(new, for: spec.id)
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
                    ForEach(spec.programs) { program in
                        Pill(text: program.title, symbol: program.symbol, color: Theme.violet)
                    }
                    if coachingOn && !store.isPro {
                        Pill(text: String(localized: "Free coach"), symbol: "waveform", color: Theme.accent)
                    }
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

struct ProgramDetailView: View {
    let program: ExerciseProgram
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var router: AppRouter
    @AppStorage("level") private var levelRaw = Level.beginner.rawValue

    private var level: Level { Level(rawValue: levelRaw) ?? .beginner }
    private var session: [ExerciseSpec] { ProgramSession.exercises(for: program) }
    private var library: [ExerciseSpec] { ExerciseLibrary.listed(in: program) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(program.title).font(.display(32, weight: .heavy)).foregroundStyle(.white)
                    Text(program.subtitle).foregroundStyle(Theme.textSecondary)
                    if !store.isPro {
                        Text("This program is part of Spotter Pro.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.violet)
                    }
                }
                .padding(.top, 8)

                Button {
                    if store.isPro {
                        let plan = ProgramSession.plan(for: program, level: level)
                        guard !plan.isEmpty else { return }
                        SpotterAnalytics.click("start_workout", screen: "program", ["program": program.rawValue])
                        router.start(ActiveWorkout(title: program.title, plan: plan))
                    } else {
                        SpotterAnalytics.click("open_paywall", screen: "program", ["source": "program", "program": program.rawValue])
                        router.showPaywall = true
                    }
                } label: {
                    Label(store.isPro ? "Start program" : "Unlock with Spotter Pro", systemImage: store.isPro ? "play.fill" : "lock.open.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: store.isPro ? Theme.accent : Theme.violet))

                Text("Today's session").eyebrow()
                ForEach(session) { spec in
                    NavigationLink(value: spec.id) {
                        ExerciseRow(spec: spec, locked: !store.isPro)
                    }
                    .buttonStyle(.plain)
                }

                if library.count > session.count {
                    Text("Full program").eyebrow()
                    ForEach(library.dropFirst(session.count)) { spec in
                        NavigationLink(value: spec.id) {
                            ExerciseRow(spec: spec, locked: !store.isPro)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(program.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
