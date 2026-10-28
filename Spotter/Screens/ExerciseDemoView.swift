import SwiftUI
import UIKit

/// Looping figure on the exercise page, so the movement is visible before the set starts.
struct ExerciseDemoHero: View {
    let spec: ExerciseSpec

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0, paused: reduceMotion)) { context in
            let clock = ExerciseDemo.clock(for: spec, at: context.date, still: reduceMotion)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.surface)
                RadialGradient(colors: [Theme.accent.opacity(0.22), .clear], center: .center, startRadius: 4, endRadius: 220)
                ExerciseManCanvas(frame: ExerciseDemo.frame(for: spec.id, clock: clock))
                    .padding(.bottom, 28)
                Text(ExerciseDemo.cue(for: spec, clock: clock))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 248)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Demonstration of \(spec.name)"))
    }
}

enum ExerciseDemo {
    struct Clock {
        var phase: CGFloat
        var depth: CGFloat
    }

    static func clock(for spec: ExerciseSpec, at date: Date, still: Bool) -> Clock {
        let period = period(for: spec.id)
        let t = date.timeIntervalSinceReferenceDate
        let phase = CGFloat(t.truncatingRemainder(dividingBy: period) / period)
        if still {
            return Clock(phase: 0.5, depth: spec.kind.isHold ? 1 : 1)
        }
        let wave = CGFloat((1 - cos(Double(phase) * 2 * .pi)) / 2)
        let depth = spec.kind.isHold ? (0.82 + 0.18 * wave) : wave
        return Clock(phase: phase, depth: depth)
    }

    static func cue(for spec: ExerciseSpec, clock: Clock) -> String {
        if case .hold(let cfg) = spec.kind { return cfg.positionCue }
        let down = spec.steps.count > 1 ? spec.steps[1] : (spec.steps.first ?? "")
        let up = spec.steps.last ?? down
        return clock.phase < 0.5 ? down : up
    }

    static func frame(for id: String, clock: Clock) -> ManFrame {
        body(for: id, phase: clock.phase, depth: clock.depth).rendered()
    }

    private static func period(for id: String) -> Double {
        switch id {
        case "highKnees", "buttKick", "jumpingJack", "mountainClimber", "flutterKick", "bicycleCrunch":
            return 1.6
        case "burpee":
            return 3.4
        case "plank", "wallSit", "sidePlank", "hollowHold", "childsPose", "downwardDog", "hipFlexorStretch", "hamstringStretch":
            return 3.2
        default:
            return 2.7
        }
    }

    // MARK: - Body

    fileprivate struct Body {
        var torso: CGFloat = 8
        var arm: CGFloat = 168
        var elbow: CGFloat = 0
        var thigh: CGFloat = 174
        var shin: CGFloat = 176
        var backThigh: CGFloat = 176
        var backShin: CGFloat = 176
        var nose: CGFloat = 78
        var hop: CGFloat = 0
        var front = false
        var span: CGFloat = 0.09
        var armLift: CGFloat = 0
        var kneeLift: CGFloat = 0
        var kneeLiftR: CGFloat = 0
        var lean: CGFloat = 0
        var squat: CGFloat = 0
        var contact: Contact = .feet

        enum Contact { case feet, hands, kneesAndHands, handsAndFeet, hip, shouldersAndFeet }

        func lerp(_ other: Body, _ t: CGFloat) -> Body {
            func m(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
            var copy = self
            copy.torso = m(torso, other.torso)
            copy.arm = m(arm, other.arm)
            copy.elbow = m(elbow, other.elbow)
            copy.thigh = m(thigh, other.thigh)
            copy.shin = m(shin, other.shin)
            copy.backThigh = m(backThigh, other.backThigh)
            copy.backShin = m(backShin, other.backShin)
            copy.nose = m(nose, other.nose)
            copy.hop = m(hop, other.hop)
            copy.front = other.front
            copy.span = m(span, other.span)
            copy.armLift = m(armLift, other.armLift)
            copy.kneeLift = m(kneeLift, other.kneeLift)
            copy.kneeLiftR = m(kneeLiftR, other.kneeLiftR)
            copy.lean = m(lean, other.lean)
            copy.squat = m(squat, other.squat)
            copy.contact = other.contact
            return copy
        }

        func rendered() -> ManFrame {
            front ? renderFront() : renderSide()
        }

        private func renderSide() -> ManFrame {
            let hip = CGPoint.zero
            let shoulder = pt(hip, 0.22, torso)
            let head = pt(shoulder, 0.07, torso)
            let face = pt(head, 0.028, nose)
            let elbowPt = pt(shoulder, 0.12, arm)
            let wrist = pt(elbowPt, 0.11, arm + self.elbow)
            let kneePt = pt(hip, 0.18, thigh)
            let ankle = pt(kneePt, 0.18, shin)
            let hipB = CGPoint(x: hip.x - 0.02, y: hip.y + 0.005)
            let kneeB = pt(hipB, 0.18, backThigh)
            let ankleB = pt(kneeB, 0.18, backShin)
            let shoulderF = CGPoint(x: shoulder.x - 0.028, y: shoulder.y - 0.008)
            let elbowF = pt(shoulderF, 0.12, arm)
            let wristF = pt(elbowF, 0.11, arm + self.elbow)
            let raw = RawMan(head: head, face: face, shoulder: shoulder, elbow: elbowPt, wrist: wrist,
                             hip: hip, knee: kneePt, ankle: ankle, shoulderF: shoulderF, elbowF: elbowF, wristF: wristF,
                             hipB: hipB, kneeB: kneeB, ankleB: ankleB)
            return place(raw, farFirst: true)
        }

        private func renderFront() -> ManFrame {
            let hip = CGPoint(x: lean, y: squat * 0.02)
            let shoulder = CGPoint(x: lean * 1.3, y: hip.y - 0.22)
            let head = CGPoint(x: shoulder.x, y: shoulder.y - 0.07)
            let face = CGPoint(x: head.x, y: head.y + 0.012)
            let ls = CGPoint(x: shoulder.x - 0.07, y: shoulder.y)
            let rs = CGPoint(x: shoulder.x + 0.07, y: shoulder.y)
            let lDir = 180 + armLift * 90
            let rDir = 180 - armLift * 90
            let lElb = pt(ls, 0.13, lDir)
            let lW = pt(lElb, 0.12, lDir + elbow)
            let rElb = pt(rs, 0.13, rDir)
            let rW = pt(rElb, 0.12, rDir - elbow)
            let lh = CGPoint(x: hip.x - span, y: hip.y)
            let rh = CGPoint(x: hip.x + span, y: hip.y)
            let bend = squat
            let lk = CGPoint(x: lh.x - bend * 0.03, y: lh.y + 0.18 * (1 - 0.45 * bend) - kneeLift * 0.12)
            let la = CGPoint(x: lh.x - span * 0.25, y: lk.y + 0.18 * (1 - 0.2 * bend) - kneeLift * 0.1)
            let rk = CGPoint(x: rh.x + bend * 0.03, y: rh.y + 0.18 * (1 - 0.45 * bend) - kneeLiftR * 0.12)
            let ra = CGPoint(x: rh.x + span * 0.25, y: rk.y + 0.18 * (1 - 0.2 * bend) - kneeLiftR * 0.1)
            let raw = RawMan(head: head, face: face, shoulder: rs, elbow: rElb, wrist: rW,
                             hip: rh, knee: rk, ankle: ra, shoulderF: ls, elbowF: lElb, wristF: lW,
                             hipB: lh, kneeB: lk, ankleB: la)
            return place(raw, farFirst: false)
        }

        private func place(_ raw: RawMan, farFirst: Bool) -> ManFrame {
            let anchor = anchorPoint(raw)
            let dy = (contact == .hands ? 0.16 : 0.86 - hop) - anchor.y
            let xs = [raw.head, raw.shoulder, raw.hip, raw.ankle, raw.ankleB, raw.wrist, raw.wristF, raw.knee, raw.kneeB].map(\.x)
            let midX = ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2
            let dx = 0.50 - midX
            func s(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }
            let near: [[CGPoint]] = [
                [s(raw.shoulder), s(raw.hip)],
                [s(raw.shoulder), s(raw.elbow), s(raw.wrist)],
                [s(raw.hip), s(raw.knee), s(raw.ankle)]
            ]
            let far: [[CGPoint]] = [
                [s(raw.shoulderF), s(raw.hipB)],
                [s(raw.shoulderF), s(raw.elbowF), s(raw.wristF)],
                [s(raw.hipB), s(raw.kneeB), s(raw.ankleB)]
            ]
            return ManFrame(head: s(raw.head), face: s(raw.face), far: farFirst ? far : [], near: (farFirst ? [] : far) + near)
        }

        private func anchorPoint(_ raw: RawMan) -> CGPoint {
            func lowest(_ points: [CGPoint]) -> CGPoint {
                points.max { $0.y < $1.y } ?? raw.ankle
            }
            switch contact {
            case .feet:
                return lowest([raw.ankle, raw.ankleB])
            case .hands:
                return raw.wrist
            case .kneesAndHands:
                return lowest([raw.knee, raw.kneeB, raw.wrist, raw.wristF])
            case .handsAndFeet:
                return lowest([raw.ankle, raw.ankleB, raw.wrist, raw.wristF])
            case .hip:
                return raw.hip
            case .shouldersAndFeet:
                let foot = lowest([raw.ankle, raw.ankleB])
                return CGPoint(x: (raw.shoulder.x + foot.x) / 2, y: max(raw.shoulder.y, foot.y))
            }
        }
    }

    fileprivate struct RawMan {
        var head, face, shoulder, elbow, wrist: CGPoint
        var hip, knee, ankle: CGPoint
        var shoulderF, elbowF, wristF: CGPoint
        var hipB, kneeB, ankleB: CGPoint
    }

    struct ManFrame {
        var head: CGPoint
        var face: CGPoint
        var far: [[CGPoint]]
        var near: [[CGPoint]]
    }

    private static func pt(_ origin: CGPoint, _ len: CGFloat, _ deg: CGFloat) -> CGPoint {
        let r = deg * .pi / 180
        return CGPoint(x: origin.x + len * sin(r), y: origin.y - len * cos(r))
    }

    // MARK: - Motions

    private static func body(for id: String, phase: CGFloat, depth: CGFloat) -> Body {
        switch id {
        case "squat", "sumoSquat":
            return mix(stand, id == "sumoSquat" ? sumo : squat, depth)
        case "frontSquat":
            return mix(stand, frontSquat, depth)
        case "squatJump":
            return jump(from: squat, phase: phase, depth: depth)
        case "lunge", "forwardLunge", "bulgarianSplit", "hipFlexorStretch":
            return mix(stand, id == "bulgarianSplit" ? bulgarian : lunge, depth)
        case "jumpLunge":
            return switchingLunge(phase)
        case "sideLunge":
            return mix(frontStand, sideLunge, depth)
        case "skater":
            return skater(phase)
        case "stepUp":
            return stepUp(depth)
        case "wallSit":
            return mix(squat, wallSit, depth)
        case "rdl", "goodMorning", "hamstringStretch":
            return mix(stand, id == "goodMorning" ? goodMorning : hinge, depth)
        case "deadlift":
            return mix(stand, deadlift, depth)
        case "pushUp", "diamondPushUp", "kneePushUp", "inclinePushUp", "declinePushUp":
            return mix(pushTop(id), pushBottom(id), depth)
        case "pikePushUp":
            return mix(pikeTop, pikeBottom, depth)
        case "plank":
            return mix(plankSoft, plankTight, depth)
        case "dip":
            return mix(dipTop, dipBottom, depth)
        case "gluteBridge", "frogPump":
            return mix(bridgeDown, id == "frogPump" ? frogTop : bridgeUp, depth)
        case "hipThrust", "singleLegBridge":
            return mix(bridgeDown, id == "singleLegBridge" ? singleBridge : thrustUp, depth)
        case "bench":
            return mix(benchDown, benchUp, depth)
        case "bicepCurl", "hammerCurl":
            return mix(curlDown, curlUp, depth)
        case "overheadPress", "pushPress":
            return id == "pushPress" ? pushPress(phase: phase, depth: depth) : mix(pressDown, pressUp, depth)
        case "lateralRaise":
            return mix(frontStand, lateralUp, depth)
        case "frontRaise":
            return mix(stand, frontRaise, depth)
        case "row", "pendlayRow", "invertedRow", "rearDeltFly", "facePull":
            return mix(rowStart(id), rowFinish(id), depth)
        case "uprightRow":
            return mix(frontStand, uprightRow, depth)
        case "tricepKickback":
            return mix(kickStart, kickFinish, depth)
        case "pullUp", "chinUp":
            return mix(hang, pull, depth)
        case "crunch", "sitUp", "toeReach":
            return mix(lieKnees, id == "sitUp" ? sitUp : (id == "toeReach" ? toeReach : crunch), depth)
        case "bicycleCrunch":
            return bicycle(phase)
        case "legRaise", "flutterKick":
            return id == "flutterKick" ? flutter(phase) : mix(lieFlat, legRaise, depth)
        case "reverseCrunch":
            return mix(lieKnees, reverseCrunch, depth)
        case "vUp":
            return mix(lieFlat, vUp, depth)
        case "hollowHold":
            return mix(lieFlat, hollow, depth)
        case "sidePlank":
            return mix(sidePlankLow, sidePlankHigh, depth)
        case "russianTwist":
            return russian(phase)
        case "mountainClimber":
            return climber(phase)
        case "jumpingJack":
            return mix(frontStand, jackOpen, depth)
        case "highKnees":
            return march(phase, high: true)
        case "buttKick":
            return buttKick(phase)
        case "burpee":
            return burpee(phase)
        case "deadBug":
            return deadBug(phase)
        case "birdDog":
            return birdDog(phase)
        case "superman":
            return mix(lieFace, superman, depth)
        case "donkeyKick":
            return mix(allFours, donkey, depth)
        case "fireHydrant":
            return mix(allFours, hydrant, depth)
        case "catCow":
            return mix(cow, cat, depth)
        case "thoracicOpen":
            return mix(allFours, thoracic, depth)
        case "downwardDog":
            return mix(plankTight, downDog, depth)
        case "childsPose":
            return mix(allFours, child, depth)
        case "worldsGreatest":
            return mix(lunge, worlds, depth)
        default:
            return mix(stand, squat, depth)
        }
    }

    private static func mix(_ a: Body, _ b: Body, _ t: CGFloat) -> Body { a.lerp(b, t) }

    private static let stand = Body()
    private static let frontStand = Body(front: true, span: 0.08, contact: .feet)

    private static let squat = Body(torso: 38, arm: 78, elbow: -12, thigh: 98, shin: 168, backThigh: 102, backShin: 166, nose: 70)
    private static let sumo = Body(torso: 18, arm: 70, thigh: 118, shin: 150, backThigh: 242, backShin: 200, nose: 80, front: true, span: 0.16, squat: 1)
    private static let frontSquat = Body(torso: 22, arm: 55, elbow: -70, thigh: 100, shin: 168, backThigh: 104, backShin: 166, nose: 75)
    private static let wallSit = Body(torso: 8, arm: 150, thigh: 96, shin: 170, backThigh: 100, backShin: 168, nose: 80)
    private static let lunge = Body(torso: 14, arm: 150, thigh: 108, shin: 162, backThigh: 238, backShin: 196, nose: 78)
    private static let bulgarian = Body(torso: 16, arm: 145, thigh: 104, shin: 160, backThigh: 250, backShin: 210, nose: 76)
    private static let sideLunge = Body(front: true, span: 0.2, armLift: 0.15, squat: 0.85)
    private static let hinge = Body(torso: 78, arm: 168, thigh: 148, shin: 170, backThigh: 152, backShin: 168, nose: 70)
    private static let goodMorning = Body(torso: 76, arm: 18, elbow: -130, thigh: 150, shin: 172, backThigh: 154, backShin: 170, nose: 68)
    private static let deadlift = Body(torso: 58, arm: 155, thigh: 118, shin: 155, backThigh: 122, backShin: 152, nose: 72)

    private static let plankTight = Body(torso: 82, arm: 118, thigh: 262, shin: 258, backThigh: 258, backShin: 255, nose: 80, contact: .handsAndFeet)
    private static let plankSoft = Body(torso: 74, arm: 112, thigh: 258, shin: 255, backThigh: 255, backShin: 252, nose: 75, contact: .handsAndFeet)
    private static let dipTop = Body(torso: 12, arm: 185, elbow: 8, thigh: 150, shin: 168, backThigh: 158, backShin: 166, contact: .feet)
    private static let dipBottom = Body(torso: 18, arm: 215, elbow: -55, thigh: 142, shin: 160, backThigh: 150, backShin: 158, contact: .feet)

    private static let bridgeDown = Body(torso: 88, arm: 170, thigh: 115, shin: 70, backThigh: 118, backShin: 68, nose: 40, contact: .shouldersAndFeet)
    private static let bridgeUp = Body(torso: 28, arm: 165, thigh: 78, shin: 96, backThigh: 82, backShin: 94, nose: 50, contact: .shouldersAndFeet)
    private static let frogTop = Body(torso: 30, arm: 160, thigh: 60, shin: 110, backThigh: 300, backShin: 250, nose: 50, contact: .shouldersAndFeet)
    private static let thrustUp = Body(torso: 8, arm: 168, thigh: 82, shin: 98, backThigh: 86, backShin: 96, nose: 70, contact: .shouldersAndFeet)
    private static let singleBridge = Body(torso: 24, arm: 165, thigh: 80, shin: 98, backThigh: 40, backShin: 30, nose: 55, contact: .shouldersAndFeet)

    private static let benchDown = Body(torso: 88, arm: 200, elbow: -95, thigh: 150, shin: 168, backThigh: 154, backShin: 166, nose: 50, contact: .hip)
    private static let benchUp = Body(torso: 88, arm: 20, elbow: -8, thigh: 150, shin: 168, backThigh: 154, backShin: 166, nose: 55, contact: .hip)
    private static let curlDown = Body(arm: 168, elbow: 6)
    private static let curlUp = Body(arm: 162, elbow: -145, nose: 75)
    private static let pressDown = Body(elbow: -95, front: true, span: 0.08, armLift: 0.35)
    private static let pressUp = Body(elbow: -8, front: true, span: 0.08, armLift: 1.72)
    private static let lateralUp = Body(elbow: -18, front: true, span: 0.08, armLift: 1.05)
    private static let jackOpen = Body(front: true, span: 0.2, armLift: 1.45)
    private static let frontRaise = Body(torso: 6, arm: 82, elbow: -16, nose: 75)
    private static let uprightRow = Body(elbow: -75, front: true, span: 0.08, armLift: 1.05)
    private static let kickStart = Body(torso: 78, arm: 95, elbow: -95, thigh: 155, shin: 168, backThigh: 158, backShin: 166, nose: 70)
    private static let kickFinish = Body(torso: 78, arm: 88, elbow: 4, thigh: 155, shin: 168, backThigh: 158, backShin: 166, nose: 70)
    private static let hang = Body(torso: 4, arm: 8, elbow: 4, thigh: 176, shin: 176, backThigh: 178, backShin: 176, contact: .hands)
    private static let pull = Body(torso: 8, arm: 42, elbow: -125, thigh: 174, shin: 176, backThigh: 176, backShin: 176, nose: 85, contact: .hands)

    private static let lieKnees = Body(torso: 86, arm: 150, thigh: 118, shin: 62, backThigh: 122, backShin: 64, nose: 40, contact: .hip)
    private static let lieFlat = Body(torso: 90, arm: 168, thigh: 96, shin: 94, backThigh: 98, backShin: 96, nose: 30, contact: .hip)
    private static let lieFace = Body(torso: 92, arm: 88, thigh: 96, shin: 94, backThigh: 98, backShin: 96, nose: 100, contact: .hip)
    private static let crunch = Body(torso: 52, arm: 130, elbow: -40, thigh: 112, shin: 64, backThigh: 116, backShin: 66, nose: 55, contact: .hip)
    private static let sitUp = Body(torso: 18, arm: 70, thigh: 112, shin: 66, backThigh: 116, backShin: 68, nose: 75, contact: .hip)
    private static let toeReach = Body(torso: 48, arm: 55, thigh: 28, shin: 22, backThigh: 32, backShin: 24, nose: 60, contact: .hip)
    private static let legRaise = Body(torso: 90, arm: 175, thigh: 28, shin: 18, backThigh: 32, backShin: 20, nose: 35, contact: .hip)
    private static let reverseCrunch = Body(torso: 78, arm: 170, thigh: 48, shin: 40, backThigh: 52, backShin: 42, nose: 40, contact: .hip)
    private static let vUp = Body(torso: 42, arm: 48, thigh: 42, shin: 36, backThigh: 46, backShin: 38, nose: 60, contact: .hip)
    private static let hollow = Body(torso: 72, arm: 40, thigh: 62, shin: 58, backThigh: 66, backShin: 60, nose: 45, contact: .hip)
    private static let sidePlankLow = Body(torso: 96, arm: 175, thigh: 268, shin: 264, backThigh: 266, backShin: 262, nose: 80, contact: .handsAndFeet)
    private static let sidePlankHigh = Body(torso: 84, arm: 172, thigh: 262, shin: 258, backThigh: 260, backShin: 256, nose: 82, contact: .handsAndFeet)

    private static let allFours = Body(torso: 86, arm: 168, thigh: 188, shin: 255, backThigh: 192, backShin: 258, nose: 80, contact: .kneesAndHands)
    private static let donkey = Body(torso: 84, arm: 170, thigh: 186, shin: 255, backThigh: 318, backShin: 300, nose: 78, contact: .kneesAndHands)
    private static let hydrant = Body(torso: 86, arm: 170, thigh: 188, shin: 250, backThigh: 250, backShin: 200, nose: 80, contact: .kneesAndHands)
    private static let cow = Body(torso: 78, arm: 165, thigh: 190, shin: 255, backThigh: 194, backShin: 258, nose: 55, contact: .kneesAndHands)
    private static let cat = Body(torso: 108, arm: 175, thigh: 186, shin: 255, backThigh: 190, backShin: 258, nose: 130, contact: .kneesAndHands)
    private static let thoracic = Body(torso: 86, arm: 12, elbow: -20, thigh: 188, shin: 255, backThigh: 192, backShin: 258, nose: 40, contact: .kneesAndHands)
    private static let downDog = Body(torso: 42, arm: 128, thigh: 228, shin: 236, backThigh: 232, backShin: 238, nose: 110, contact: .handsAndFeet)
    private static let child = Body(torso: 132, arm: 150, thigh: 210, shin: 255, backThigh: 214, backShin: 258, nose: 140, contact: .kneesAndHands)
    private static let worlds = Body(torso: 48, arm: 8, elbow: -15, thigh: 108, shin: 160, backThigh: 236, backShin: 198, nose: 40)
    private static let superman = Body(torso: 68, arm: 48, thigh: 62, shin: 58, backThigh: 66, backShin: 60, nose: 55, contact: .hip)

    private static func pushTop(_ id: String) -> Body {
        switch id {
        case "kneePushUp":
            return Body(torso: 70, arm: 112, thigh: 210, shin: 250, backThigh: 214, backShin: 252, nose: 78, contact: .handsAndFeet)
        case "inclinePushUp":
            return Body(torso: 58, arm: 108, thigh: 250, shin: 246, backThigh: 248, backShin: 244, nose: 75, contact: .handsAndFeet)
        case "declinePushUp":
            return Body(torso: 98, arm: 120, thigh: 250, shin: 255, backThigh: 248, backShin: 252, nose: 70, contact: .handsAndFeet)
        default:
            return plankSoft
        }
    }

    private static func pushBottom(_ id: String) -> Body {
        var top = pushTop(id)
        top.torso += 16
        top.arm += 18
        top.elbow = -62
        top.nose += 8
        return top
    }

    private static let pikeTop = Body(torso: 48, arm: 118, thigh: 230, shin: 236, backThigh: 234, backShin: 238, nose: 100, contact: .handsAndFeet)
    private static let pikeBottom = Body(torso: 62, arm: 145, elbow: -70, thigh: 226, shin: 234, backThigh: 230, backShin: 236, nose: 115, contact: .handsAndFeet)

    private static func rowStart(_ id: String) -> Body {
        let hinged = Body(torso: id == "pendlayRow" ? 88 : 80, arm: 155, thigh: 150, shin: 168, backThigh: 154, backShin: 166, nose: 72)
        if id == "rearDeltFly" || id == "facePull" {
            return Body(torso: 80, arm: 168, elbow: id == "facePull" ? -20 : 0, thigh: 152, shin: 168, backThigh: 156, backShin: 166, nose: 70)
        }
        if id == "invertedRow" {
            return Body(torso: 78, arm: 95, thigh: 255, shin: 250, backThigh: 252, backShin: 248, nose: 75, contact: .handsAndFeet)
        }
        return hinged
    }

    private static func rowFinish(_ id: String) -> Body {
        var start = rowStart(id)
        if id == "rearDeltFly" {
            start.arm = 70
            return start
        }
        if id == "facePull" {
            start.arm = 55
            start.elbow = -85
            return start
        }
        start.elbow = -110
        start.arm = id == "invertedRow" ? 70 : 130
        return start
    }

    private static func jump(from bottom: Body, phase: CGFloat, depth: CGFloat) -> Body {
        if phase < 0.55 { return mix(stand, bottom, depth) }
        let t = min(1, (phase - 0.55) / 0.2)
        var up = mix(bottom, stand, t)
        up.hop = sin(t * .pi) * 0.1
        return up
    }

    private static func pushPress(phase: CGFloat, depth: CGFloat) -> Body {
        if phase < 0.35 {
            return mix(pressDown, Body(torso: 20, elbow: -95, thigh: 140, shin: 160, backThigh: 144, backShin: 158, front: true, span: 0.08, armLift: 0.35, squat: 0.45), phase / 0.35)
        }
        return mix(pressDown, pressUp, min(1, (phase - 0.28) / 0.45))
    }

    private static func switchingLunge(_ phase: CGFloat) -> Body {
        let other = Body(torso: 14, arm: 150, thigh: 238, shin: 196, backThigh: 108, backShin: 162, nose: 78)
        if phase < 0.4 { return lunge }
        if phase > 0.62 { return other }
        let t = (phase - 0.4) / 0.22
        var mid = mix(lunge, other, t)
        mid.hop = sin(t * .pi) * 0.09
        return mid
    }

    private static func stepUp(_ depth: CGFloat) -> Body {
        let onStep = Body(torso: 8, arm: 150, thigh: 168, shin: 174, backThigh: 200, backShin: 188, hop: 0.07)
        let ready = Body(torso: 12, arm: 155, thigh: 112, shin: 158, backThigh: 176, backShin: 174)
        return mix(ready, onStep, depth)
    }

    private static func skater(_ phase: CGFloat) -> Body {
        let left = Body(front: true, span: 0.16, armLift: 0.35, lean: -0.1, squat: 0.7)
        let right = Body(front: true, span: 0.16, armLift: 0.35, lean: 0.1, squat: 0.7)
        if phase < 0.42 { return left }
        if phase > 0.58 { return right }
        return mix(left, right, (phase - 0.42) / 0.16)
    }

    private static func march(_ phase: CGFloat, high: Bool) -> Body {
        let lift = max(0, sin(phase * 2 * .pi))
        let liftR = max(0, sin(phase * 2 * .pi + .pi))
        var b = frontStand
        b.kneeLift = lift * (high ? 1 : 0.7)
        b.kneeLiftR = liftR * (high ? 1 : 0.7)
        b.armLift = 0.25 + 0.15 * lift
        return b
    }

    private static func buttKick(_ phase: CGFloat) -> Body {
        let kick = max(0, sin(phase * 2 * .pi))
        let kickR = max(0, sin(phase * 2 * .pi + .pi))
        var b = stand
        b.shin = 176 - kick * 110
        b.backShin = 176 - kickR * 110
        return b
    }

    private static func burpee(_ phase: CGFloat) -> Body {
        let squatDown = squat
        if phase < 0.22 { return mix(stand, squatDown, phase / 0.22) }
        if phase < 0.42 { return mix(squatDown, plankTight, (phase - 0.22) / 0.2) }
        if phase < 0.62 { return mix(plankTight, squatDown, (phase - 0.42) / 0.2) }
        var up = mix(squatDown, stand, (phase - 0.62) / 0.38)
        if phase > 0.72 && phase < 0.9 {
            up.hop = sin((phase - 0.72) / 0.18 * .pi) * 0.08
        }
        return up
    }

    private static func climber(_ phase: CGFloat) -> Body {
        let drive = max(0, sin(phase * 2 * .pi))
        var b = plankTight
        b.thigh = 262 - drive * 150
        b.shin = 258 - drive * 40
        return b
    }

    private static func bicycle(_ phase: CGFloat) -> Body {
        let drive = max(0, sin(phase * 2 * .pi))
        var b = crunch
        b.thigh = 112 - drive * 70
        b.backThigh = 40 + drive * 70
        b.torso = 58
        b.nose = 40 + drive * 30
        return b
    }

    private static func flutter(_ phase: CGFloat) -> Body {
        let wave = sin(phase * 2 * .pi)
        var b = legRaise
        b.thigh = 36 + wave * 14
        b.backThigh = 36 - wave * 14
        return b
    }

    private static func russian(_ phase: CGFloat) -> Body {
        var b = Body(elbow: -40, front: true, span: 0.1, armLift: 0.45, squat: 0.95)
        b.lean = sin(phase * 2 * .pi) * 0.14
        return b
    }

    private static func deadBug(_ phase: CGFloat) -> Body {
        let drive = max(0, sin(phase * 2 * .pi))
        var b = lieKnees
        b.arm = 150 - drive * 120
        b.thigh = 118 - (1 - drive) * 70
        b.shin = 62 + (1 - drive) * 90
        b.contact = .hip
        return b
    }

    private static func birdDog(_ phase: CGFloat) -> Body {
        let drive = max(0, sin(phase * 2 * .pi))
        var b = allFours
        b.arm = 168 - drive * 150
        b.backThigh = 192 + drive * 80
        b.backShin = 258 - drive * 20
        b.nose = 80 - drive * 30
        return b
    }
}

private struct ExerciseManCanvas: View {
    let frame: ExerciseDemo.ManFrame

    var body: some View {
        Canvas { context, size in
            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * size.width, y: p.y * size.height)
            }
            var floor = Path()
            floor.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.88))
            floor.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.88))
            context.stroke(floor, with: .color(Color.white.opacity(0.16)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            let width = max(7, size.height * 0.034)
            func chains(_ lines: [[CGPoint]]) -> [Path] {
                lines.compactMap { chain in
                    guard let first = chain.first else { return nil }
                    var path = Path()
                    path.move(to: map(first))
                    for point in chain.dropFirst() { path.addLine(to: map(point)) }
                    return path
                }
            }
            let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 10))
                for path in chains(frame.far + frame.near) {
                    layer.stroke(path, with: .color(Theme.accent.opacity(0.55)), style: StrokeStyle(lineWidth: width + 6, lineCap: .round, lineJoin: .round))
                }
            }
            for path in chains(frame.far) {
                context.stroke(path, with: .color(Theme.accent.opacity(0.4)), style: StrokeStyle(lineWidth: width * 0.85, lineCap: .round, lineJoin: .round))
            }
            for path in chains(frame.near) {
                context.stroke(path, with: .color(Theme.accent), style: style)
            }

            let head = map(frame.head)
            let radius = size.height * 0.058
            let headRect = CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: headRect), with: .color(Theme.accent))
            let eye = map(frame.face)
            let dot = size.height * 0.012
            context.fill(Path(ellipseIn: CGRect(x: eye.x - dot, y: eye.y - dot, width: dot * 2, height: dot * 2)), with: .color(Theme.bg))
        }
    }
}
