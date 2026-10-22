import Foundation
import CoreGraphics

enum Geo {
    /// Angle ABC at vertex B, in degrees (0...180).
    static func angle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        let v1 = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let mag = hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)
        guard mag > 0 else { return 180 }
        let cosine = max(-1, min(1, (v1.dx * v2.dx + v1.dy * v2.dy) / mag))
        return Double(acos(cosine)) * 180 / .pi
    }

    /// How far the segment from -> to tilts away from vertical, in degrees (0 = vertical, 90 = horizontal).
    static func angleFromVertical(from: CGPoint, to: CGPoint) -> Double {
        let dx = abs(to.x - from.x)
        let dy = abs(to.y - from.y)
        return Double(atan2(dx, dy)) * 180 / .pi
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    /// Perpendicular distance of `p` from the line a–c. Positive means `p` is below the line
    /// (towards the floor in image space), negative means above.
    static func offsetBelowLine(_ p: CGPoint, a: CGPoint, c: CGPoint) -> CGFloat {
        let dx = c.x - a.x, dy = c.y - a.y
        let len = hypot(dx, dy)
        guard len > 0 else { return 0 }
        var nx = -dy / len, ny = dx / len
        if ny < 0 { nx = -nx; ny = -ny }
        return (p.x - a.x) * nx + (p.y - a.y) * ny
    }
}

// MARK: - Body measurements used by the form rules

extension Pose {
    func angle(_ a: Joint, _ b: Joint, _ c: Joint) -> Double? {
        guard let pa = px(a), let pb = px(b), let pc = px(c) else { return nil }
        return Geo.angle(pa, pb, pc)
    }

    func kneeAngle(_ s: Side) -> Double? { angle(s.hip, s.knee, s.ankle) }
    func hipAngle(_ s: Side) -> Double? { angle(s.shoulder, s.hip, s.knee) }
    func elbowAngle(_ s: Side) -> Double? { angle(s.shoulder, s.elbow, s.wrist) }
    /// Angle between torso and upper arm (0 = arm hanging by the side).
    func armToTorso(_ s: Side) -> Double? { angle(s.hip, s.shoulder, s.elbow) }

    /// Forward/backward torso tilt from vertical (side view).
    func torsoLean(_ s: Side) -> Double? {
        guard let h = px(s.hip), let sh = px(s.shoulder) else { return nil }
        return Geo.angleFromVertical(from: h, to: sh)
    }

    /// Height of the hip above the knee, measured in shin lengths.
    /// ~1.0 standing tall, ~0 with thighs parallel to the floor. Works from side or front view.
    func hipDepth(_ s: Side) -> Double? {
        guard let h = px(s.hip), let k = px(s.knee), let a = px(s.ankle) else { return nil }
        let shin = Geo.distance(k, a)
        guard shin > 1 else { return nil }
        return Double((k.y - h.y) / shin)
    }

    /// Hip offset from the straight shoulder–ankle line, as a fraction of body length.
    /// Positive = hips sagging towards the floor, negative = hips piked up.
    func bodyLineOffset(_ s: Side) -> Double? {
        guard let sh = px(s.shoulder), let hip = px(s.hip) else { return nil }
        guard let end = px(s.ankle) ?? px(s.knee) else { return nil }
        let len = Geo.distance(sh, end)
        guard len > 1 else { return nil }
        return Double(Geo.offsetBelowLine(hip, a: sh, c: end) / len)
    }

    /// Tilt of the whole body line (shoulder → ankle) from vertical. ~90 when lying flat.
    func bodyTilt(_ s: Side) -> Double? {
        guard let sh = px(s.shoulder), let end = px(s.ankle) ?? px(s.knee) else { return nil }
        return Geo.angleFromVertical(from: end, to: sh)
    }

    var torsoLength: CGFloat? {
        let pairs: [(Joint, Joint)] = [(.leftShoulder, .leftHip), (.rightShoulder, .rightHip)]
        let lengths = pairs.compactMap { a, b -> CGFloat? in
            guard let pa = px(a), let pb = px(b) else { return nil }
            return Geo.distance(pa, pb)
        }
        guard !lengths.isEmpty else { return nil }
        return lengths.reduce(0, +) / CGFloat(lengths.count)
    }

    /// True when the person faces the camera (shoulders appear wide relative to torso length).
    var isFrontFacing: Bool {
        guard let ls = px(.leftShoulder), let rs = px(.rightShoulder),
              let lh = px(.leftHip), let rh = px(.rightHip) else { return false }
        let torso = Geo.distance(Geo.mid(ls, rs), Geo.mid(lh, rh))
        guard torso > 0 else { return false }
        return abs(ls.x - rs.x) / torso > 0.45
    }

    /// Front view: knees collapsing inward relative to the ankles.
    func kneesCaving() -> Bool {
        guard isFrontFacing,
              let lk = px(.leftKnee), let rk = px(.rightKnee),
              let la = px(.leftAnkle), let ra = px(.rightAnkle) else { return false }
        let ankleWidth = abs(la.x - ra.x)
        guard ankleWidth > 10 else { return false }
        return abs(lk.x - rk.x) < ankleWidth * 0.8
    }

    /// Height difference between the wrists, as a fraction of torso length.
    var wristImbalance: Double? {
        guard let lw = px(.leftWrist), let rw = px(.rightWrist), let torso = torsoLength, torso > 0 else { return nil }
        return Double(abs(lw.y - rw.y) / torso)
    }

    /// Average of a measurement over both sides (whichever are visible).
    func bothSides(_ f: (Side) -> Double?) -> Double? {
        let values = [f(.left), f(.right)].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
