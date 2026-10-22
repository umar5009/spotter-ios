import Foundation

struct RepResult {
    let score: Int
    let faults: [String]
}

struct FrameFeedback {
    enum Event {
        case rep(RepResult)
        case partial(String)
    }

    var progress: Double = 0
    var activeFaults: [FormRule] = []
    var inPosition: Bool? = nil
    var event: Event? = nil
}

/// Turns a stream of poses into reps, form scores and live corrections for one exercise.
final class ExerciseAnalyzer {
    static let tempoCue = "Slow down on the way down"

    let spec: ExerciseSpec
    private(set) var side: Side = .right

    private enum Phase { case rest, moving }
    private var phase: Phase = .rest
    private var sideLocked = false
    private var maxProgress = 0.0
    private var reachedPeak = false
    private var startTime: TimeInterval = 0
    private var peakTime: TimeInterval?
    private var peakExitTime: TimeInterval?
    private var repFaults: [String: FormRule] = [:]

    // Holds
    private(set) var holdSeconds: Double = 0
    private var goodHoldSeconds: Double = 0
    private var lastTime: TimeInterval?
    private(set) var holdFaultCounts: [String: Int] = [:]

    init(spec: ExerciseSpec) {
        self.spec = spec
    }

    var holdScore: Int {
        guard holdSeconds > 0 else { return 0 }
        return Int((goodHoldSeconds / holdSeconds * 100).rounded())
    }

    func reset() {
        phase = .rest
        maxProgress = 0
        reachedPeak = false
        peakTime = nil
        peakExitTime = nil
        repFaults = [:]
        holdSeconds = 0
        goodHoldSeconds = 0
        lastTime = nil
        holdFaultCounts = [:]
        sideLocked = false
    }

    func process(_ pose: Pose) -> FrameFeedback {
        updateSide(pose)
        switch spec.kind {
        case .reps(let config): return processReps(pose, config)
        case .hold(let config): return processHold(pose, config)
        }
    }

    // MARK: - Private

    private func updateSide(_ pose: Pose) {
        if !sideLocked {
            side = pose.bestSide
            sideLocked = true
        } else if phase == .rest, pose.sideConfidence(side.opposite) > pose.sideConfidence(side) + 0.8 {
            side = side.opposite
        }
    }

    private func faults(in pose: Pose, progress: Double) -> [FormRule] {
        spec.rules.filter { rule in
            if rule.when == .bottom && progress < 0.75 { return false }
            return rule.isFault(pose, side)
        }
    }

    private func processReps(_ pose: Pose, _ cfg: RepConfig) -> FrameFeedback {
        var feedback = FrameFeedback()
        guard let value = cfg.metric(pose, side) else { return feedback }

        let range = abs(cfg.rest - cfg.peak)
        let raw = cfg.restIsHigh ? (cfg.rest - value) / range : (value - cfg.rest) / range
        let progress = max(0, min(1.2, raw))
        feedback.progress = min(1, progress)
        let t = pose.timestamp

        switch phase {
        case .rest:
            if progress > 0.15 {
                phase = .moving
                startTime = t
                maxProgress = progress
                reachedPeak = false
                peakTime = nil
                peakExitTime = nil
                repFaults = [:]
            }

        case .moving:
            maxProgress = max(maxProgress, progress)
            if progress >= 1, !reachedPeak {
                reachedPeak = true
                peakTime = t
            }
            if reachedPeak, peakExitTime == nil, progress < 0.85 {
                peakExitTime = t
            }

            let active = faults(in: pose, progress: progress)
            feedback.activeFaults = active
            for rule in active { repFaults[rule.id] = rule }

            if progress < 0.08 {
                phase = .rest
                if reachedPeak {
                    let rules = Array(repFaults.values)
                    var score = 100 - rules.reduce(0) { $0 + $1.penalty }
                    var cues = rules.sorted { $0.penalty > $1.penalty }.map(\.cue)

                    if let minimum = cfg.minEccentricSeconds {
                        let eccentric: TimeInterval?
                        switch cfg.eccentric {
                        case .towardPeak: eccentric = peakTime.map { $0 - startTime }
                        case .towardRest: eccentric = peakExitTime.map { t - $0 }
                        }
                        if let e = eccentric, e < minimum {
                            score -= 10
                            cues.append(Self.tempoCue)
                        }
                    }
                    feedback.event = .rep(RepResult(score: max(0, score), faults: cues))
                } else if maxProgress > 0.45 {
                    feedback.event = .partial(cfg.partialCue)
                }
            }
        }
        return feedback
    }

    private func processHold(_ pose: Pose, _ cfg: HoldConfig) -> FrameFeedback {
        var feedback = FrameFeedback()
        let t = pose.timestamp
        defer { lastTime = t }

        guard cfg.inPosition(pose, side) else {
            feedback.inPosition = false
            return feedback
        }
        feedback.inPosition = true
        feedback.progress = 1

        let dt = lastTime.map { min(0.25, max(0, t - $0)) } ?? 0
        let active = spec.rules.filter { $0.isFault(pose, side) }
        holdSeconds += dt
        if active.isEmpty {
            goodHoldSeconds += dt
        } else {
            for rule in active { holdFaultCounts[rule.cue, default: 0] += 1 }
        }
        feedback.activeFaults = active
        return feedback
    }
}
