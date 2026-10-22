import Foundation
import CoreGraphics

/// All supported exercises and their AI form checks.
/// Thresholds are tuned for typical adult proportions; adjust here to make coaching stricter or looser.
enum ExerciseLibrary {
    static let all: [ExerciseSpec] = [squat, pushUp, plank, lunge, gluteBridge, romanianDeadlift, overheadPress, bicepCurl, lateralRaise]
    static let freeIDs: Set<String> = Set(all.filter(\.isFree).map(\.id))

    static func spec(_ id: String) -> ExerciseSpec { all.first { $0.id == id } ?? squat }

    // MARK: Home

    static let squat = ExerciseSpec(
        id: "squat", name: String(localized: "Squat"), category: .home,
        equipment: String(localized: "Bodyweight · Goblet · Barbell"),
        muscles: [String(localized: "Quads"), String(localized: "Glutes"), String(localized: "Core")],
        symbol: "figure.strengthtraining.functional",
        camera: .side, isFree: true,
        required: [.shoulder, .hip, .knee, .ankle], bothSidesRequired: false,
        kind: .reps(RepConfig(
            metric: { p, s in p.hipDepth(s) },
            restIsHigh: true, rest: 0.75, peak: 0.15,
            partialCue: String(localized: "Go deeper. Aim for thighs parallel to the floor."),
            eccentric: .towardPeak, minEccentricSeconds: nil)),
        rules: [
            FormRule(id: "squat.chest", cue: String(localized: "Keep your chest up"), when: .bottom, penalty: 20,
                     highlight: [.shoulder, .hip]) { p, s in (p.torsoLean(s) ?? 0) > 55 },
            FormRule(id: "squat.knees", cue: String(localized: "Push your knees out"), when: .bottom, penalty: 20,
                     highlight: [.knee], bothSides: true) { p, _ in p.kneesCaving() }
        ],
        steps: [
            String(localized: "Feet shoulder-width apart, toes turned out slightly."),
            String(localized: "Brace your core and sit your hips back and down."),
            String(localized: "Lower until your thighs are parallel to the floor."),
            String(localized: "Drive through your whole foot to stand tall.")
        ],
        note: String(localized: "Filming from the front? Spotter also checks if your knees cave in."))

    static let pushUp = ExerciseSpec(
        id: "pushUp", name: String(localized: "Push-up"), category: .home,
        equipment: String(localized: "Bodyweight"),
        muscles: [String(localized: "Chest"), String(localized: "Triceps"), String(localized: "Shoulders"), String(localized: "Core")],
        symbol: "figure.strengthtraining.traditional",
        camera: .side, isFree: true,
        required: [.shoulder, .elbow, .wrist, .hip, .knee], bothSidesRequired: false,
        kind: .reps(RepConfig(
            metric: { p, s in p.elbowAngle(s) },
            restIsHigh: true, rest: 150, peak: 95,
            partialCue: String(localized: "Lower your chest closer to the floor."))),
        rules: [
            FormRule(id: "push.sag", cue: String(localized: "Squeeze your glutes. Hips are sagging"), penalty: 20,
                     highlight: [.hip]) { p, s in (p.bodyLineOffset(s) ?? 0) > 0.06 },
            FormRule(id: "push.pike", cue: String(localized: "Lower your hips into a straight line"), penalty: 15,
                     highlight: [.hip]) { p, s in (p.bodyLineOffset(s) ?? 0) < -0.08 }
        ],
        steps: [
            String(localized: "Hands just wider than shoulders, body in one straight line."),
            String(localized: "Lower your chest until your elbows reach about 90°."),
            String(localized: "Keep elbows angled roughly 45° from your body."),
            String(localized: "Press the floor away and lock out at the top.")
        ],
        note: String(localized: "Too hard? Do them from your knees. Spotter still checks your body line."))

    static let plank = ExerciseSpec(
        id: "plank", name: String(localized: "Plank"), category: .home,
        equipment: String(localized: "Bodyweight"),
        muscles: [String(localized: "Core"), String(localized: "Shoulders"), String(localized: "Glutes")],
        symbol: "figure.core.training",
        camera: .side, isFree: true,
        required: [.shoulder, .hip, .ankle], bothSidesRequired: false,
        kind: .hold(HoldConfig(
            inPosition: { p, s in (p.bodyTilt(s) ?? 0) > 55 },
            positionCue: String(localized: "Get into your plank position"))),
        rules: [
            FormRule(id: "plank.sag", cue: String(localized: "Hips are sagging. Brace your core"), penalty: 0,
                     highlight: [.hip]) { p, s in (p.bodyLineOffset(s) ?? 0) > 0.05 },
            FormRule(id: "plank.pike", cue: String(localized: "Lower your hips slightly"), penalty: 0,
                     highlight: [.hip]) { p, s in (p.bodyLineOffset(s) ?? 0) < -0.07 }
        ],
        steps: [
            String(localized: "Forearms under shoulders, legs straight behind you."),
            String(localized: "Squeeze glutes and brace like someone will poke your stomach."),
            String(localized: "Keep a straight line from head to heels."),
            String(localized: "Breathe steadily. Spotter only counts time held with good form.")
        ])

    static let lunge = ExerciseSpec(
        id: "lunge", name: String(localized: "Reverse Lunge"), category: .home,
        equipment: String(localized: "Bodyweight · Dumbbells"),
        muscles: [String(localized: "Quads"), String(localized: "Glutes"), String(localized: "Balance")],
        symbol: "figure.cross.training",
        camera: .side, isFree: false,
        required: [.shoulder, .hip, .knee, .ankle], bothSidesRequired: false,
        kind: .reps(RepConfig(
            metric: { p, _ in [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() },
            restIsHigh: true, rest: 155, peak: 105,
            partialCue: String(localized: "Drop your back knee closer to the floor."))),
        rules: [
            FormRule(id: "lunge.torso", cue: String(localized: "Stay tall. Keep your torso upright"), when: .bottom, penalty: 15,
                     highlight: [.shoulder, .hip]) { p, s in (p.torsoLean(s) ?? 0) > 28 }
        ],
        steps: [
            String(localized: "Stand tall, then step one foot back."),
            String(localized: "Lower until both knees bend to about 90°."),
            String(localized: "Keep your front knee over your foot."),
            String(localized: "Push through the front heel to return. Alternate legs.")
        ])

    static let gluteBridge = ExerciseSpec(
        id: "gluteBridge", name: String(localized: "Glute Bridge"), category: .home,
        equipment: String(localized: "Bodyweight · Mat"),
        muscles: [String(localized: "Glutes"), String(localized: "Hamstrings"), String(localized: "Lower back")],
        symbol: "figure.cooldown",
        camera: .side, isFree: false,
        required: [.shoulder, .hip, .knee, .ankle], bothSidesRequired: false,
        kind: .reps(RepConfig(
            metric: { p, s in p.hipAngle(s) },
            restIsHigh: false, rest: 145, peak: 168,
            partialCue: String(localized: "Drive your hips higher and squeeze at the top."),
            eccentric: .towardRest, minEccentricSeconds: nil)),
        rules: [
            FormRule(id: "bridge.feet", cue: String(localized: "Move your feet so your knees bend to about 90°"), when: .bottom, penalty: 10,
                     highlight: [.knee, .ankle]) { p, s in
                guard let k = p.kneeAngle(s) else { return false }
                return k < 65 || k > 120
            }
        ],
        steps: [
            String(localized: "Lie on your back, knees bent, feet flat and hip-width apart."),
            String(localized: "Press through your heels and lift your hips."),
            String(localized: "Squeeze your glutes hard at the top. Ribs stay down."),
            String(localized: "Lower slowly with control.")
        ])

    // MARK: Gym

    static let romanianDeadlift = ExerciseSpec(
        id: "rdl", name: String(localized: "Romanian Deadlift"), category: .gym,
        equipment: String(localized: "Barbell · Dumbbells"),
        muscles: [String(localized: "Hamstrings"), String(localized: "Glutes"), String(localized: "Back")],
        symbol: "figure.strengthtraining.traditional",
        camera: .side, isFree: false,
        required: [.shoulder, .wrist, .hip, .knee, .ankle], bothSidesRequired: false,
        kind: .reps(RepConfig(
            metric: { p, s in p.hipAngle(s) },
            restIsHigh: true, rest: 160, peak: 115,
            partialCue: String(localized: "Hinge a little further. Feel the stretch in your hamstrings."),
            eccentric: .towardPeak, minEccentricSeconds: 1.0)),
        rules: [
            FormRule(id: "rdl.knees", cue: String(localized: "Push your hips back. Less knee bend"), when: .bottom, penalty: 15,
                     highlight: [.knee]) { p, s in (p.kneeAngle(s) ?? 180) < 130 },
            FormRule(id: "rdl.bar", cue: String(localized: "Keep the weight close to your legs"), when: .bottom, penalty: 15,
                     highlight: [.wrist]) { p, s in
                guard let w = p.px(s.wrist), let k = p.px(s.knee), let torso = p.torsoLength, torso > 0 else { return false }
                return abs(w.x - k.x) / torso > 0.4
            }
        ],
        steps: [
            String(localized: "Stand tall holding the weight in front of your thighs."),
            String(localized: "Soften your knees, then push your hips straight back."),
            String(localized: "Slide the weight down your legs until you feel a hamstring stretch."),
            String(localized: "Squeeze your glutes to stand back up.")
        ],
        note: String(localized: "A phone camera can't reliably see spinal rounding. Keep a neutral back and use a weight you control."))

    static let overheadPress = ExerciseSpec(
        id: "overheadPress", name: String(localized: "Overhead Press"), category: .gym,
        equipment: String(localized: "Dumbbells · Barbell"),
        muscles: [String(localized: "Shoulders"), String(localized: "Triceps"), String(localized: "Upper chest")],
        symbol: "figure.strengthtraining.traditional",
        camera: .front, isFree: false,
        required: [.shoulder, .elbow, .wrist, .hip], bothSidesRequired: true,
        kind: .reps(RepConfig(
            metric: { p, _ in p.bothSides { p.elbowAngle($0) } },
            restIsHigh: false, rest: 100, peak: 160,
            partialCue: String(localized: "Lock out fully overhead."),
            eccentric: .towardRest, minEccentricSeconds: 0.8)),
        rules: [
            FormRule(id: "press.even", cue: String(localized: "Press both arms evenly"), penalty: 15,
                     highlight: [.wrist, .elbow], bothSides: true) { p, _ in (p.wristImbalance ?? 0) > 0.18 }
        ],
        steps: [
            String(localized: "Start with the weights at shoulder height, elbows under wrists."),
            String(localized: "Brace your core and squeeze your glutes. Ribs stay down."),
            String(localized: "Press straight up until your arms lock out."),
            String(localized: "Lower slowly back to your shoulders.")
        ])

    static let bicepCurl = ExerciseSpec(
        id: "bicepCurl", name: String(localized: "Bicep Curl"), category: .gym,
        equipment: String(localized: "Dumbbells · Barbell · Cable"),
        muscles: [String(localized: "Biceps"), String(localized: "Forearms")],
        symbol: "dumbbell.fill",
        camera: .side, isFree: false,
        required: [.shoulder, .elbow, .wrist, .hip], bothSidesRequired: false,
        kind: .reps(RepConfig(
            metric: { p, s in p.elbowAngle(s) },
            restIsHigh: true, rest: 145, peak: 65,
            partialCue: String(localized: "Curl all the way up."),
            eccentric: .towardRest, minEccentricSeconds: 0.8)),
        rules: [
            FormRule(id: "curl.elbow", cue: String(localized: "Pin your elbows to your sides"), penalty: 15,
                     highlight: [.elbow, .shoulder]) { p, s in (p.armToTorso(s) ?? 0) > 35 },
            FormRule(id: "curl.swing", cue: String(localized: "Stop swinging. Stand tall"), penalty: 20,
                     highlight: [.shoulder, .hip]) { p, s in (p.torsoLean(s) ?? 0) > 15 }
        ],
        steps: [
            String(localized: "Stand tall with the weights at your sides, palms forward."),
            String(localized: "Keep your upper arms still and curl the weight up."),
            String(localized: "Squeeze at the top without moving your elbows forward."),
            String(localized: "Lower slowly. Fighting the weight down builds muscle.")
        ])

    static let lateralRaise = ExerciseSpec(
        id: "lateralRaise", name: String(localized: "Lateral Raise"), category: .gym,
        equipment: String(localized: "Dumbbells · Cable"),
        muscles: [String(localized: "Side delts"), String(localized: "Upper traps")],
        symbol: "figure.arms.open",
        camera: .front, isFree: false,
        required: [.shoulder, .elbow, .hip], bothSidesRequired: true,
        kind: .reps(RepConfig(
            metric: { p, _ in p.bothSides { p.armToTorso($0) } },
            restIsHigh: false, rest: 30, peak: 75,
            partialCue: String(localized: "Raise to shoulder height."),
            eccentric: .towardRest, minEccentricSeconds: 0.8)),
        rules: [
            FormRule(id: "raise.high", cue: String(localized: "Stop at shoulder height"), penalty: 10,
                     highlight: [.elbow, .shoulder], bothSides: true) { p, _ in (p.bothSides { p.armToTorso($0) } ?? 0) > 110 },
            FormRule(id: "raise.even", cue: String(localized: "Raise both arms evenly"), penalty: 15,
                     highlight: [.wrist, .elbow], bothSides: true) { p, _ in (p.wristImbalance ?? 0) > 0.2 }
        ],
        steps: [
            String(localized: "Stand tall with light dumbbells at your sides."),
            String(localized: "Slight bend in the elbows. Lead with your elbows, not your hands."),
            String(localized: "Raise out to the sides until your arms reach shoulder height."),
            String(localized: "Lower slowly. No shrugging.")
        ])
}
