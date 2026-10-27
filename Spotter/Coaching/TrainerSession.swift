import SwiftUI
import QuartzCore

struct Cue: Equatable {
    enum Kind { case good, warn, info }
    let text: String
    let kind: Kind
}

struct SetResult: Identifiable {
    let id = UUID()
    let exerciseID: String
    let exerciseName: String
    let setNumber: Int
    let reps: Int
    let holdSeconds: Int
    let avgScore: Int
    let faults: [String: Int]
    let weightKg: Double
    /// False when this set was rep-counted without live form coaching.
    let coached: Bool

    var topFault: String? { faults.max { $0.value < $1.value }?.key }
}

/// Drives a live workout: framing check → countdown → coached set → rest → next set/exercise.
final class TrainerSession: ObservableObject {
    enum Stage: Equatable {
        case framing
        case countdown(Int)
        case active
        case resting(Int)
        case exerciseDone
        case finished
    }

    @Published private(set) var stage: Stage = .framing
    @Published private(set) var index = 0
    @Published private(set) var setNumber = 1
    @Published private(set) var repCount = 0
    @Published private(set) var holdSeconds: Double = 0
    @Published private(set) var lastRepScore: Int?
    @Published private(set) var progress: Double = 0
    @Published private(set) var cue: Cue?
    @Published private(set) var faultJoints: Set<Joint> = []
    @Published private(set) var inFrame = false
    @Published private(set) var results: [SetResult] = []
    @Published var weightKg: Double
    @Published private(set) var focusCue: String?

    let plan: [PlannedExercise]
    let title: String
    let sessionID = UUID()
    let startedAt = Date()

    private var analyzer: ExerciseAnalyzer
    private var repScores: [Int] = []
    private var faultCounts: [String: Int] = [:]
    private var inFrameSince: TimeInterval?
    private var outOfFrameSince: TimeInterval?
    private var timer: Timer?
    private var cueClear: DispatchWorkItem?
    private var perfectStreak = 0
    private var lastHoldAnnouncement = 0
    private var watched: [String: String] = [:]
    private let voice = VoiceCoach.shared
    /// Exercise IDs that receive live form cues and form-score talk.
    private let coachedIDs: Set<String>

    var liveCoaching: Bool { coachedIDs.contains(spec.id) }

    var current: PlannedExercise { plan[index] }
    var spec: ExerciseSpec { ExerciseLibrary.spec(current.exerciseID) }
    var target: Int { current.target }
    var isHold: Bool { spec.kind.isHold }
    var nextSpec: ExerciseSpec? { index + 1 < plan.count ? ExerciseLibrary.spec(plan[index + 1].exerciseID) : nil }
    var currentExerciseResults: [SetResult] { results.filter { $0.exerciseID == current.exerciseID } }

    init(plan: [PlannedExercise], title: String, coachedIDs: Set<String>) {
        precondition(!plan.isEmpty, "A workout needs at least one exercise")
        self.plan = plan
        self.title = title
        self.coachedIDs = coachedIDs
        self.analyzer = ExerciseAnalyzer(spec: ExerciseLibrary.spec(plan[0].exerciseID))
        self.weightKg = LiftLoad.resolved(plan[0])
    }

    func begin(watching: [String: String]) {
        watched = watching
        refreshFocus()
        voice.say(openingLine(setup: true), key: "setup", cooldown: 0, priority: true)
    }

    func adjustLoad(by direction: Int, unit: Measure.Weight) {
        setLoad(LiftLoad.stepped(weightKg, direction: direction, unit: unit))
    }

    func setLoad(_ kilograms: Double) {
        let clamped = max(0, min(500, kilograms))
        weightKg = clamped
        guard spec.category == .gym else { return }
        LiftLoad.save(clamped, for: spec.id)
    }

    // MARK: - Frame handling

    func handle(_ pose: Pose?) {
        let now = CACurrentMediaTime()
        let framed = pose.map { self.isFramed($0) } ?? false
        if inFrame != framed { inFrame = framed }

        switch stage {
        case .framing:
            if framed {
                if inFrameSince == nil { inFrameSince = now }
                if let since = inFrameSince, now - since > 1.0 { startCountdown() }
            } else {
                inFrameSince = nil
            }

        case .active:
            guard let pose else {
                setFaultJoints([])
                return
            }
            if framed {
                outOfFrameSince = nil
            } else {
                if outOfFrameSince == nil { outOfFrameSince = now }
                if let since = outOfFrameSince, now - since > 1.2 {
                    let cue = String(localized: "Step back so I can see your whole body")
                    show(Cue(text: cue, kind: .info))
                    voice.say(cue, key: "frame", cooldown: 8)
                }
            }

            let feedback = analyzer.process(pose)
            if abs(feedback.progress - progress) > 0.01 { progress = feedback.progress }

            if liveCoaching {
                setFaultJoints(joints(for: feedback.activeFaults))
                if let fault = preferred(feedback.activeFaults).first {
                    show(Cue(text: fault.cue, kind: .warn))
                    voice.say(fault.cue, key: fault.id, cooldown: 5)
                }
            } else {
                setFaultJoints([])
            }

            if isHold { updateHold(feedback) }

            switch feedback.event {
            case .rep(let result):
                registerRep(result)
            case .partial(let text):
                let line = liveCoaching ? text : String(localized: "Finish the full range so it counts.")
                show(Cue(text: line, kind: .warn))
                voice.say(line, key: "partial", cooldown: 3, priority: true)
                Haptics.warning()
            case nil: break
            }

        default:
            break
        }
    }

    private func isFramed(_ pose: Pose) -> Bool {
        let sides: [Side] = spec.bothSidesRequired ? [.left, .right] : [pose.bestSide]
        for side in sides {
            for role in spec.required where !pose.has(role.joint(side)) { return false }
        }
        return true
    }

    private func joints(for rules: [FormRule]) -> Set<Joint> {
        var set = Set<Joint>()
        let side = analyzer.side
        for rule in rules {
            for role in rule.highlight {
                set.insert(role.joint(side))
                if rule.bothSides { set.insert(role.joint(side.opposite)) }
            }
        }
        return set
    }

    private func setFaultJoints(_ joints: Set<Joint>) {
        if faultJoints != joints { faultJoints = joints }
    }

    private func updateHold(_ feedback: FrameFeedback) {
        holdSeconds = analyzer.holdSeconds
        if feedback.inPosition == false {
            let line = String(localized: "Get into position")
            show(Cue(text: line, kind: .info))
            if liveCoaching, case .hold(let cfg) = spec.kind {
                voice.say(cfg.positionCue, key: "position", cooldown: 6)
            }
        }
        let remaining = target - Int(holdSeconds)
        if remaining != lastHoldAnnouncement {
            if remaining == 10 && target > 15 { voice.say(String(localized: "Ten seconds left"), key: "hold10", cooldown: 0, priority: true) }
            if remaining == target / 2 && target >= 20 { voice.say(String(localized: "Halfway"), key: "holdHalf", cooldown: 0, priority: true) }
            lastHoldAnnouncement = remaining
        }
        if holdSeconds >= Double(target) { completeSet() }
    }

    private func registerRep(_ result: RepResult) {
        repCount += 1
        Haptics.rep()
        let remaining = target - repCount

        if liveCoaching {
            lastRepScore = result.score
            repScores.append(result.score)
            for fault in result.faults { faultCounts[fault, default: 0] += 1 }
            var spoken = ["\(repCount)"]
            if let fault = preferred(result.faults).first {
                spoken.append(fault)
                perfectStreak = 0
                show(Cue(text: fault, kind: .warn))
            } else {
                if result.score >= 90 { perfectStreak += 1 }
                if perfectStreak > 0 && perfectStreak % 4 == 0 { spoken.append(String(localized: "Perfect form")) }
                show(Cue(text: String(localized: "Great rep · \(result.score)"), kind: .good))
            }
            if remaining == 2 && target >= 6 { spoken.append(String(localized: "Two more")) }
            if remaining == 1 && target >= 4 { spoken.append(String(localized: "Last one")) }
            voice.say(spoken.joined(separator: ". "), key: "rep", cooldown: 0, priority: true)
        } else {
            var spoken = ["\(repCount)"]
            if remaining == 2 && target >= 6 { spoken.append(String(localized: "Two more")) }
            if remaining == 1 && target >= 4 { spoken.append(String(localized: "Last one")) }
            show(Cue(text: String(localized: "Rep \(repCount)"), kind: .good))
            voice.say(spoken.joined(separator: ". "), key: "rep", cooldown: 0, priority: true)
        }

        if repCount >= target { completeSet() }
    }

    // MARK: - Flow

    func completeSet() {
        guard stage == .active else { return }
        let average: Int
        let faults: [String: Int]
        if liveCoaching && isHold {
            average = analyzer.holdScore
            faults = analyzer.holdFaultCounts
        } else if liveCoaching {
            average = repScores.isEmpty ? 0 : repScores.reduce(0, +) / repScores.count
            faults = faultCounts
        } else {
            average = 0
            faults = [:]
        }
        results.append(SetResult(exerciseID: spec.id, exerciseName: spec.name, setNumber: setNumber,
                                 reps: isHold ? 0 : repCount, holdSeconds: Int(holdSeconds),
                                 avgScore: average, faults: faults, weightKg: weightKg, coached: liveCoaching))
        if let cue = watched[spec.id], faults[cue] == nil {
            watched.removeValue(forKey: spec.id)
        }
        refreshFocus()
        Haptics.success()
        setFaultJoints([])

        if setNumber < current.sets {
            let line = liveCoaching
                ? String(localized: "Set \(setNumber) done. Form score \(average). Rest up.")
                : String(localized: "Set \(setNumber) done. Rest up.")
            voice.say(line, key: "setDone", cooldown: 0, priority: true)
            startRest()
        } else {
            let line = liveCoaching
                ? String(localized: "\(spec.name) complete. Average form \(average).")
                : String(localized: "\(spec.name) complete.")
            voice.say(line, key: "exerciseDone", cooldown: 0, priority: true)
            timer?.invalidate()
            stage = .exerciseDone
        }
    }

    func skipRest() {
        guard case .resting = stage else { return }
        nextSet()
    }

    func addRest(_ seconds: Int) {
        if case .resting(let remaining) = stage { stage = .resting(remaining + seconds) }
    }

    func continueToNextExercise() {
        guard index + 1 < plan.count else {
            finish()
            return
        }
        index += 1
        setNumber = 1
        analyzer = ExerciseAnalyzer(spec: spec)
        weightKg = LiftLoad.resolved(current)
        resetSetState()
        refreshFocus()
        inFrameSince = nil
        stage = .framing
        voice.say(openingLine(setup: false), key: "next", cooldown: 0, priority: true)
    }

    func finish() {
        if stage == .active, repCount > 0 || holdSeconds > 1 { completeSet() }
        timer?.invalidate()
        stage = .finished
        voice.say(String(localized: "Workout complete. Great work."), key: "finished", cooldown: 0, priority: true)
    }

    func stopAll() {
        timer?.invalidate()
        cueClear?.cancel()
        voice.stop()
    }

    private func startCountdown() {
        resetSetState()
        stage = .countdown(3)
        voice.say(String(localized: "Three"), key: "count", cooldown: 0, priority: true)
        runTimer { [weak self] in
            guard let self, case .countdown(let n) = self.stage else { return }
            if n <= 1 {
                self.timer?.invalidate()
                self.analyzer.reset()
                self.stage = .active
                self.voice.say(String(localized: "Go"), key: "count", cooldown: 0, priority: true)
            } else {
                self.stage = .countdown(n - 1)
                self.voice.say(n - 1 == 2 ? String(localized: "Two") : String(localized: "One"), key: "count", cooldown: 0, priority: true)
            }
        }
    }

    private func startRest() {
        stage = .resting(current.restSeconds)
        runTimer { [weak self] in
            guard let self, case .resting(let remaining) = self.stage else { return }
            if remaining <= 1 {
                self.nextSet()
            } else {
                if remaining - 1 == 5 { self.voice.say(String(localized: "Get ready"), key: "ready", cooldown: 0, priority: true) }
                self.stage = .resting(remaining - 1)
            }
        }
    }

    private func nextSet() {
        timer?.invalidate()
        setNumber += 1
        startCountdown()
    }

    private func refreshFocus() {
        let next = liveCoaching ? watched[spec.id] : nil
        if focusCue != next { focusCue = next }
    }

    private func openingLine(setup: Bool) -> String {
        let base = setup
            ? String(localized: "Let's set up. \(spec.camera.instruction)")
            : String(localized: "Next up: \(spec.name). \(spec.camera.instruction)")
        guard liveCoaching, let cue = watched[spec.id] else { return base }
        return base + " " + String(localized: "Last time: \(cue).")
    }

    private func preferred(_ rules: [FormRule]) -> [FormRule] {
        guard let watch = watched[spec.id], let index = rules.firstIndex(where: { $0.cue == watch }) else { return rules }
        var copy = rules
        copy.insert(copy.remove(at: index), at: 0)
        return copy
    }

    private func preferred(_ cues: [String]) -> [String] {
        guard let watch = watched[spec.id], let index = cues.firstIndex(of: watch) else { return cues }
        var copy = cues
        copy.insert(copy.remove(at: index), at: 0)
        return copy
    }

    private func resetSetState() {
        repCount = 0
        holdSeconds = 0
        repScores = []
        faultCounts = [:]
        lastRepScore = nil
        progress = 0
        perfectStreak = 0
        lastHoldAnnouncement = 0
        outOfFrameSince = nil
        analyzer.reset()
        cue = nil
    }

    private func runTimer(_ tick: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick() }
    }

    private func show(_ newCue: Cue) {
        if cue != newCue {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { cue = newCue }
        }
        cueClear?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.cue = nil }
        }
        cueClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}
