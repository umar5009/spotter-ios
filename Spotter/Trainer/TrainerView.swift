import SwiftUI
import SwiftData
import AVFoundation

/// The live AI personal-trainer screen.
struct TrainerView: View {
    let workout: ActiveWorkout

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var camera = CameraManager()
    @StateObject private var session: TrainerSession
    @State private var poseStream = PoseStream()
    @State private var demo: DemoPoseSource?
    @State private var saved = false
    @State private var confirmExit = false
    @AppStorage("voiceEnabled") private var voiceEnabled = true
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue

    init(workout: ActiveWorkout) {
        self.workout = workout
        _session = StateObject(wrappedValue: TrainerSession(plan: workout.plan, title: workout.title))
    }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private var cameraBlocked: Bool {
        demo == nil && (camera.authorization == .denied || camera.authorization == .restricted || !camera.isAvailable)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if demo != nil {
                DemoBackdrop().ignoresSafeArea()
            } else if camera.authorization == .authorized {
                CameraPreview(session: camera.session).ignoresSafeArea()
            }

            SkeletonLayer(stream: poseStream, faultJoints: session.faultJoints, active: session.stage == .active)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom).frame(height: 200)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).frame(height: 320)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if session.stage == .finished {
                WorkoutSummaryView(session: session) { close() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if cameraBlocked {
                CameraBlockedView(denied: camera.authorization != .authorized, onClose: close)
            } else {
                hud
            }
        }
        .statusBarHidden()
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: session.stage)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onChange(of: session.stage) { _, newStage in
            if newStage == .finished { persist() }
        }
        .confirmationDialog("End this workout?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Save and finish") {
                SpotterAnalytics.click("save_and_finish", screen: "workout")
                session.finish()
            }
            Button("Discard workout", role: .destructive) {
                SpotterAnalytics.click("discard_workout", screen: "workout")
                close()
            }
            Button("Keep training", role: .cancel) {
                SpotterAnalytics.click("keep_training", screen: "workout")
            }
        }
    }

    // MARK: - HUD

    private var hud: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                planProgress.padding(.top, 12)
                CueBanner(cue: session.cue).padding(.top, 14)
                if demo != nil {
                    Pill(text: "Simulator demo · animated squat", symbol: "sparkles", color: Theme.violet).padding(.top, 8)
                }
                Spacer()
                bottomArea
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if session.stage == .active && !session.isHold {
                HStack {
                    Spacer()
                    DepthBar(progress: session.progress)
                        .frame(height: 220)
                        .padding(.trailing, 14)
                }
                .transition(.opacity)
            }

            if case .countdown(let n) = session.stage {
                CountdownView(number: n)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            CircleIconButton(symbol: "xmark") {
                SpotterAnalytics.click(session.results.isEmpty ? "close_workout" : "end_workout_prompt", screen: "workout")
                if session.results.isEmpty { close() } else { confirmExit = true }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.spec.name)
                    .font(.display(19, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            CircleIconButton(symbol: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill") {
                voiceEnabled.toggle()
                SpotterAnalytics.click("voice_coaching", screen: "workout", ["enabled": voiceEnabled ? "true" : "false"])
                Haptics.tap()
            }
            if demo == nil {
                CircleIconButton(symbol: "arrow.triangle.2.circlepath.camera") {
                    SpotterAnalytics.click("flip_camera", screen: "workout")
                    camera.flipCamera()
                    Haptics.tap()
                }
            }
        }
        .padding(.top, 8)
    }

    private var subtitle: String {
        let unit = session.isHold ? String(localized: "s hold") : String(localized: " reps")
        var text = String(localized: "Set \(session.setNumber) of \(session.current.sets) · \(session.target)\(unit)")
        if session.weightKg > 0 {
            let unit = Measure.Weight(rawValue: weightUnitRaw) ?? .kilograms
            text += " · \(Measure.format(unit.fromKilograms(session.weightKg))) \(unit.symbol)"
        }
        return text
    }

    private var planProgress: some View {
        HStack(spacing: 4) {
            ForEach(Array(workout.plan.enumerated()), id: \.offset) { i, _ in
                Capsule()
                    .fill(i < session.index ? Theme.accent : (i == session.index ? Color.white : Color.white.opacity(0.2)))
                    .frame(height: 4)
            }
        }
    }

    @ViewBuilder
    private var bottomArea: some View {
        switch session.stage {
        case .framing:
            FramingCard(spec: session.spec, inFrame: session.inFrame)
        case .countdown, .active:
            activePanel
        case .resting(let seconds):
            RestCard(session: session, seconds: seconds)
        case .exerciseDone:
            ExerciseDoneCard(session: session)
        case .finished:
            EmptyView()
        }
    }

    private var activePanel: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.isHold ? "\(Int(session.holdSeconds))" : "\(session.repCount)")
                        .font(.system(size: 84, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: session.repCount)
                    Text(session.isHold
                         ? String(localized: "of \(session.target) seconds")
                         : String(localized: "of \(session.target) reps"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                VStack(spacing: 6) {
                    ScoreRing(score: session.isHold ? nil : session.lastRepScore, size: 68, lineWidth: 7)
                    Text(session.isHold ? String(localized: "Form") : String(localized: "Last rep")).eyebrow(.white.opacity(0.6))
                }
            }
            if session.stage == .active {
                Button {
                    SpotterAnalytics.click("finish_set", screen: "workout")
                    session.completeSet()
                } label: {
                    Label("Finish set", systemImage: "checkmark")
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.08)))
    }

    // MARK: - Lifecycle

    private func start() {
        UIApplication.shared.isIdleTimerDisabled = true
        let stream = poseStream
        let trainer = session
        if isSimulator {
            let source = DemoPoseSource()
            source.onPose = { pose in
                stream.pose = pose
                trainer.handle(pose)
            }
            demo = source
            source.start()
        } else {
            camera.onPose = { pose in
                stream.pose = pose
                trainer.handle(pose)
            }
            camera.requestAccessAndStart()
        }
        session.begin()
        SpotterAnalytics.screen("workout")
    }

    private func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
        camera.onPose = nil
        camera.stop()
        demo?.stop()
        session.stopAll()
    }

    private func close() {
        stop()
        dismiss()
    }

    private func persist() {
        guard !saved, !session.results.isEmpty else { return }
        saved = true
        let results = session.results
        let reps = results.reduce(0) { $0 + $1.reps }
        let average = results.reduce(0) { $0 + $1.avgScore } / max(1, results.count)
        let log = WorkoutLog(id: session.sessionID, date: .now, title: session.title,
                             durationSeconds: Int(Date().timeIntervalSince(session.startedAt)),
                             totalReps: reps, avgFormScore: average, setCount: results.count)
        modelContext.insert(log)
        for r in results {
            let faults = r.faults.flatMap { Array(repeating: $0.key, count: $0.value) }
            modelContext.insert(SetLog(date: .now, sessionID: session.sessionID, exerciseID: r.exerciseID,
                                       exerciseName: r.exerciseName, setNumber: r.setNumber, reps: r.reps,
                                       holdSeconds: r.holdSeconds, avgFormScore: r.avgScore,
                                       weightKg: r.weightKg, faults: faults))
        }
        try? modelContext.save()
        SpotterAnalytics.log("workout_complete", [
            "title": session.title,
            "reps": reps,
            "form_score": average,
            "duration_seconds": Int(Date().timeIntervalSince(session.startedAt)),
            "set_count": results.count
        ])
    }
}

// MARK: - Overlays

struct CueBanner: View {
    let cue: Cue?

    var body: some View {
        ZStack {
            if let cue {
                HStack(spacing: 10) {
                    Image(systemName: icon(cue.kind))
                        .font(.system(size: 16, weight: .bold))
                    Text(cue.text)
                        .font(.display(16, weight: .bold))
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(cue.kind == .good ? Color.black : Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(color(cue.kind), in: Capsule())
                .shadow(color: color(cue.kind).opacity(0.5), radius: 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(cue.text)
            }
        }
        .frame(height: 50)
    }

    private func icon(_ kind: Cue.Kind) -> String {
        switch kind {
        case .good: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "viewfinder"
        }
    }

    private func color(_ kind: Cue.Kind) -> Color {
        switch kind {
        case .good: return Theme.accent
        case .warn: return Theme.bad
        case .info: return Theme.violet
        }
    }
}

struct CountdownView: View {
    let number: Int

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: 170, height: 170)
            Circle().stroke(Theme.accent, lineWidth: 4).frame(width: 170, height: 170)
            Text("\(number)")
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
        }
        .animation(.snappy, value: number)
    }
}

struct FramingCard: View {
    let spec: ExerciseSpec
    let inFrame: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: spec.camera.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up your camera").font(.display(18, weight: .bold)).foregroundStyle(.white)
                    Text(spec.camera.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            Text(spec.camera.instruction)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Circle().fill(inFrame ? Theme.accent : Theme.warn).frame(width: 9, height: 9)
                Text(inFrame ? String(localized: "Got you. Hold still…") : String(localized: "Step back until your whole body is visible"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.08), in: Capsule())
            .animation(.easeInOut, value: inFrame)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct RestCard: View {
    @ObservedObject var session: TrainerSession
    let seconds: Int

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rest").eyebrow(.white.opacity(0.6))
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: seconds)
                    Text("Next: set \(session.setNumber + 1) of \(session.current.sets)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if let last = session.results.last {
                    VStack(spacing: 6) {
                        ScoreRing(score: last.avgScore, size: 64, lineWidth: 6)
                        Text("Set form").eyebrow(.white.opacity(0.6))
                    }
                }
            }
            if let fault = session.results.last?.topFault {
                HStack(spacing: 10) {
                    Image(systemName: "target").foregroundStyle(Theme.warn)
                    Text("Focus next set: \(fault)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(12)
                .background(Theme.warn.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack(spacing: 10) {
                Button("+15 s") {
                    SpotterAnalytics.click("add_rest", screen: "workout")
                    session.addRest(15)
                }.buttonStyle(GlassButtonStyle())
                Button("Skip rest") {
                    SpotterAnalytics.click("skip_rest", screen: "workout")
                    session.skipRest()
                }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct ExerciseDoneCard: View {
    @ObservedObject var session: TrainerSession

    var body: some View {
        let sets = session.currentExerciseResults
        let average = sets.isEmpty ? 0 : sets.reduce(0) { $0 + $1.avgScore } / sets.count
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exercise complete").eyebrow(Theme.accent)
                    Text(session.spec.name).font(.display(26, weight: .heavy)).foregroundStyle(.white)
                }
                Spacer()
                ScoreRing(score: average, size: 64, lineWidth: 6)
            }
            HStack(spacing: 8) {
                ForEach(sets) { s in
                    VStack(spacing: 4) {
                        Text(session.isHold ? "\(s.holdSeconds)s" : "\(s.reps)")
                            .font(.display(18, weight: .bold)).foregroundStyle(.white)
                        Text("Set \(s.setNumber)").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                        Capsule().fill(Theme.scoreColor(s.avgScore)).frame(width: 24, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            Button {
                SpotterAnalytics.click(session.nextSpec == nil ? "finish_workout" : "next_exercise", screen: "workout")
                session.continueToNextExercise()
            } label: {
                if let next = session.nextSpec {
                    Label("Next: \(next.name)", systemImage: "arrow.right")
                } else {
                    Label("Finish workout", systemImage: "flag.checkered")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct CameraBlockedView: View {
    let denied: Bool
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "video.slash.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
            Text(denied ? String(localized: "Camera access needed") : String(localized: "Camera unavailable"))
                .font(.display(24, weight: .bold)).foregroundStyle(.white)
            Text(denied
                 ? String(localized: "Spotter watches your form through the camera. Everything is processed on your iPhone. No video is recorded or uploaded.")
                 : String(localized: "We couldn't start the camera on this device."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 24)
            if denied {
                Button("Open Settings") {
                    SpotterAnalytics.click("open_settings", screen: "workout")
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
            }
            Button("Close") {
                SpotterAnalytics.click("close_camera_prompt", screen: "workout")
                onClose()
            }.buttonStyle(GlassButtonStyle()).padding(.horizontal, 24)
            Spacer()
        }
    }
}
