import SwiftUI
import AVFoundation

struct OnboardingView: View {
    var onFinish: () -> Void

    @AppStorage("goal") private var goalRaw = Goal.strength.rawValue
    @AppStorage("place") private var placeRaw = TrainingPlace.home.rawValue
    @AppStorage("level") private var levelRaw = Level.beginner.rawValue
    @State private var step = 0
    @State private var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var coachingIDs: [String] = []

    private let lastStep = 7

    var body: some View {
        VStack(spacing: 0) {
            if step > 0 {
                HStack(spacing: 14) {
                    Button {
                        SpotterAnalytics.click("onboarding_back", screen: "onboarding", ["step": step])
                        withAnimation { step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    }
                    ProgressView(value: Double(step), total: Double(lastStep))
                        .tint(Theme.accent)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            Group {
                switch step {
                case 0: welcome
                case 1: choice(title: "What's your main goal?", subtitle: "Spotter shapes your plan and coaching around it.") {
                    ForEach(Goal.allCases) { g in
                        SelectionRow(title: g.title, subtitle: g.subtitle, symbol: g.symbol, selected: goalRaw == g.rawValue) {
                            SpotterAnalytics.click("onboarding_goal", screen: "onboarding", ["value": g.rawValue])
                            goalRaw = g.rawValue
                        }
                    }
                }
                case 2: choice(title: "Where will you train?", subtitle: "Bodyweight at home, weights at the gym, or both.") {
                    ForEach(TrainingPlace.allCases) { p in
                        SelectionRow(title: p.title, subtitle: p.subtitle, symbol: p.symbol, selected: placeRaw == p.rawValue) {
                            SpotterAnalytics.click("onboarding_place", screen: "onboarding", ["value": p.rawValue])
                            placeRaw = p.rawValue
                        }
                    }
                }
                case 3: choice(title: "How experienced are you?", subtitle: "Be honest. Good form first, then load.") {
                    ForEach(Level.allCases) { l in
                        SelectionRow(title: l.title, subtitle: l.subtitle, symbol: "chart.bar.fill", selected: levelRaw == l.rawValue) {
                            SpotterAnalytics.click("onboarding_level", screen: "onboarding", ["value": l.rawValue])
                            levelRaw = l.rawValue
                        }
                    }
                }
                case 4: choice(title: "Pick 2 exercises for free coaching", subtitle: "Live form coaching stays free on these two. Every other exercise still counts your reps. Goal programs are part of Spotter Pro.") {
                    FreeCoachingList(selected: $coachingIDs)
                }
                case 5: cameraStep
                case 6: badgesStep
                default: planReady
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            Spacer(minLength: 0)

            Button(buttonTitle) { advance() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var buttonTitle: String {
        switch step {
        case 0: return String(localized: "Get started")
        case 4: return coachingIDs.count == FreeCoaching.limit ? String(localized: "Continue") : String(localized: "Choose 2 exercises")
        case 5: return cameraGranted ? String(localized: "Continue") : String(localized: "Allow camera")
        case lastStep: return String(localized: "Start my plan")
        default: return String(localized: "Continue")
        }
    }

    private func advance() {
        Haptics.tap()
        SpotterAnalytics.click("onboarding_continue", screen: "onboarding", ["step": step])
        if step == 4 {
            guard coachingIDs.count == FreeCoaching.limit else {
                Haptics.warning()
                return
            }
            FreeCoaching.save(coachingIDs)
            SpotterAnalytics.click("free_coaching_pick", screen: "onboarding", ["exercises": coachingIDs.joined(separator: ",")])
        }
        if step == 5 && !cameraGranted {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraGranted = granted
                    withAnimation { step += 1 }
                }
            }
            return
        }
        if step >= lastStep {
            if coachingIDs.count == FreeCoaching.limit { FreeCoaching.save(coachingIDs) }
            onFinish()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { step += 1 }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            AnimatedCoachPreview()
                .frame(height: 380)
                .padding(.top, 12)
            VStack(alignment: .leading, spacing: 10) {
                Text("No gym needed. No guesswork.").eyebrow(Theme.accent)
                Text("A personal trainer that watches every rep.")
                    .font(.display(34, weight: .heavy))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Prop up your phone. Spotter counts your reps, scores your form and tells you how to fix it out loud, as you move.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
    }

    private func choice<Content: View>(title: LocalizedStringKey, subtitle: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.display(30, weight: .heavy)).foregroundStyle(.white).padding(.top, 24)
                Text(subtitle).foregroundStyle(Theme.textSecondary).padding(.bottom, 10)
                content()
            }
            .padding(.horizontal, 20)
        }
    }

    private var cameraStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How your AI coach sees you").font(.display(30, weight: .heavy)).foregroundStyle(.white).padding(.top, 24)
            feature("iphone.gen3", "Prop your phone up", "Against a wall or water bottle, 2 to 3 metres away.")
            feature("figure.stand", "Step into frame", "Spotter tracks 15 points on your body in real time.")
            feature("waveform", "Listen and adjust", "Hear rep counts and corrections like “Keep your chest up.”")
            feature("lock.shield.fill", "Private by design", "Everything runs on your iPhone. No video is recorded or uploaded.")
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var badgesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How you earn badges").font(.display(30, weight: .heavy)).foregroundStyle(.white).padding(.top, 24)
                Text("Progress recounts your saved workouts and weigh-ins. A badge stays once you qualify, even if a streak breaks.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(SpotterBadge.allCases) { badge in
                    badgeRow(badge)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private var planReady: some View {
        let plan = PlanBuilder.today(place: TrainingPlace(rawValue: placeRaw) ?? .home,
                                     level: Level(rawValue: levelRaw) ?? .beginner,
                                     goal: Goal(rawValue: goalRaw) ?? .strength,
                                     isPro: true)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your plan is ready").eyebrow(Theme.accent).padding(.top, 24)
                Text(plan.title).font(.display(32, weight: .heavy)).foregroundStyle(.white)
                HStack(spacing: 8) {
                    Pill(text: "\(plan.estimatedMinutes) min", symbol: "clock")
                    Pill(text: "3× per week", symbol: "calendar")
                    Pill(text: (Level(rawValue: levelRaw) ?? .beginner).title, symbol: "chart.bar.fill")
                }
                Card {
                    VStack(spacing: 12) {
                        ForEach(plan.items) { item in
                            let spec = ExerciseLibrary.spec(item.exerciseID)
                            HStack {
                                Image(systemName: spec.symbol).foregroundStyle(Theme.accent).frame(width: 28)
                                Text(spec.name).font(.display(16, weight: .semibold)).foregroundStyle(.white)
                                Spacer()
                                Text("\(item.sets) × \(item.target)\(spec.kind.isHold ? "s" : "")")
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                Text("Every session adapts: hit your reps with a form score above 85 and Spotter will suggest progressing.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                if FreeCoaching.displayNames.isEmpty == false {
                    Text("Live coaching is free on \(FreeCoaching.displayNames). 6-Pack, weight loss, and the other programs are part of Spotter Pro.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func badgeRow(_ badge: SpotterBadge) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: badge.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(badge.title).font(.display(17, weight: .bold)).foregroundStyle(.white)
                Text(badge.requirement).font(.subheadline).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.display(17, weight: .bold)).foregroundStyle(.white)
                Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Looping animated skeleton with live cues, used as the onboarding hero.
struct AnimatedCoachPreview: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let cycle = t.truncatingRemainder(dividingBy: 6.0)
            let depth = (1 - cos(t * 2 * .pi / 3.0)) / 2
            let leaning = cycle > 3.0
            let pose = DemoPoseSource.squat(depth: depth, lean: leaning, timestamp: t)
            let fault: Set<Joint> = leaning && depth > 0.7 ? [.rightShoulder, .rightHip] : []

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.surfaceHigh, Theme.surface], startPoint: .top, endPoint: .bottom))
                SkeletonCanvas(pose: pose, faultJoints: fault)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                HStack {
                    Pill(text: fault.isEmpty ? "Great depth" : "Keep your chest up",
                         symbol: fault.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                         color: fault.isEmpty ? Theme.accent : Theme.bad)
                    Spacer()
                    Text("\(Int(t / 3.0) % 12 + 1) reps")
                        .font(.display(15, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                }
                .padding(16)
            }
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Theme.stroke))
        }
    }
}
