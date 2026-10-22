import Foundation

enum ExerciseCategory: String {
    case home = "Home"
    case gym = "Gym"

    var title: String {
        switch self {
        case .home: return String(localized: "Home")
        case .gym: return String(localized: "Gym")
        }
    }
}

enum CameraAngle {
    case side, front

    var label: String { self == .side ? String(localized: "Side view") : String(localized: "Front view") }
    var symbol: String { self == .side ? "person.fill.turn.right" : "person.fill" }
    var instruction: String {
        switch self {
        case .side: return String(localized: "Turn side-on to the camera. Prop your phone at hip height, about 2 to 3 metres away.")
        case .front: return String(localized: "Face the camera. Prop your phone at chest height, about 2 to 3 metres away.")
        }
    }
}

/// A single form check. `isFault` returns true when the user's form is wrong in this frame.
struct FormRule: Identifiable {
    enum When {
        case moving   // any time during a rep
        case bottom   // only near the deepest point of the rep
    }

    let id: String
    let cue: String
    let when: When
    let penalty: Int
    let highlight: [JointRole]
    let bothSides: Bool
    let isFault: (Pose, Side) -> Bool

    init(id: String, cue: String, when: When = .moving, penalty: Int = 15,
         highlight: [JointRole], bothSides: Bool = false,
         isFault: @escaping (Pose, Side) -> Bool) {
        self.id = id
        self.cue = cue
        self.when = when
        self.penalty = penalty
        self.highlight = highlight
        self.bothSides = bothSides
        self.isFault = isFault
    }
}

/// Describes how a rep is counted from one body measurement.
struct RepConfig {
    enum Eccentric { case towardPeak, towardRest }

    /// The measurement tracked through the rep (an angle in degrees or a ratio).
    let metric: (Pose, Side) -> Double?
    /// Whether the metric is high at the start position (e.g. knee angle in a squat).
    let restIsHigh: Bool
    /// Metric value at the start/finish position.
    let rest: Double
    /// Metric value that counts as a full-range rep.
    let peak: Double
    /// Said when the user turns around before reaching full range.
    let partialCue: String
    /// Which half of the rep is the lowering (eccentric) phase.
    var eccentric: Eccentric = .towardPeak
    /// If set, lowering faster than this many seconds is flagged.
    var minEccentricSeconds: Double? = nil
}

struct HoldConfig {
    let inPosition: (Pose, Side) -> Bool
    let positionCue: String
}

enum ExerciseKind {
    case reps(RepConfig)
    case hold(HoldConfig)

    var isHold: Bool {
        if case .hold = self { return true }
        return false
    }
}

struct ExerciseSpec: Identifiable {
    let id: String
    let name: String
    let category: ExerciseCategory
    let equipment: String
    let muscles: [String]
    let symbol: String
    let camera: CameraAngle
    let isFree: Bool
    /// Joints that must be visible for coaching to work.
    let required: [JointRole]
    let bothSidesRequired: Bool
    let kind: ExerciseKind
    let rules: [FormRule]
    let steps: [String]
    var note: String? = nil

    var countingDescription: String {
        switch kind {
        case .reps: return String(localized: "Counts a rep only when you reach full range and return.")
        case .hold: return String(localized: "Times your hold only while your body is in position.")
        }
    }

    var tempoCheck: Bool {
        if case .reps(let cfg) = kind { return cfg.minEccentricSeconds != nil }
        return false
    }
}
