import Foundation
import QuartzCore
import CoreGraphics

/// Generates an animated squatting skeleton so the trainer can be previewed in the
/// iOS Simulator (which has no camera). Every 3rd rep leans too far forward and every
/// 5th rep is too shallow, so you can see the coaching cues fire.
final class DemoPoseSource {
    var onPose: ((Pose) -> Void)?
    private var timer: Timer?
    private var startTime: TimeInterval = 0

    func start() {
        startTime = CACurrentMediaTime()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let t = CACurrentMediaTime() - startTime
        let period = 2.8
        let rep = Int(t / period)
        let phase = t.truncatingRemainder(dividingBy: period) / period
        var depth: Double
        switch phase {
        case ..<0.15: depth = 0
        case ..<0.5: depth = Self.ease((phase - 0.15) / 0.35)
        case ..<0.6: depth = 1
        case ..<0.9: depth = 1 - Self.ease((phase - 0.6) / 0.3)
        default: depth = 0
        }
        if rep % 5 == 4 { depth *= 0.65 }
        onPose?(Self.squat(depth: depth, lean: rep % 3 == 2, timestamp: CACurrentMediaTime()))
    }

    static func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }

    // Side-view keyframes (normalized, top-left origin), facing right.
    private static let standing: [Joint: CGPoint] = [
        .nose: CGPoint(x: 0.53, y: 0.20), .neck: CGPoint(x: 0.50, y: 0.26),
        .rightShoulder: CGPoint(x: 0.50, y: 0.28), .rightElbow: CGPoint(x: 0.51, y: 0.39), .rightWrist: CGPoint(x: 0.52, y: 0.49),
        .root: CGPoint(x: 0.50, y: 0.52), .rightHip: CGPoint(x: 0.50, y: 0.52),
        .rightKnee: CGPoint(x: 0.51, y: 0.70), .rightAnkle: CGPoint(x: 0.50, y: 0.88)
    ]
    private static let bottom: [Joint: CGPoint] = [
        .nose: CGPoint(x: 0.60, y: 0.41), .neck: CGPoint(x: 0.56, y: 0.46),
        .rightShoulder: CGPoint(x: 0.55, y: 0.47), .rightElbow: CGPoint(x: 0.64, y: 0.50), .rightWrist: CGPoint(x: 0.73, y: 0.49),
        .root: CGPoint(x: 0.40, y: 0.68), .rightHip: CGPoint(x: 0.40, y: 0.68),
        .rightKnee: CGPoint(x: 0.56, y: 0.70), .rightAnkle: CGPoint(x: 0.50, y: 0.88)
    ]
    private static let bottomLean: [Joint: CGPoint] = [
        .nose: CGPoint(x: 0.76, y: 0.58), .neck: CGPoint(x: 0.71, y: 0.60),
        .rightShoulder: CGPoint(x: 0.70, y: 0.60), .rightElbow: CGPoint(x: 0.76, y: 0.68), .rightWrist: CGPoint(x: 0.82, y: 0.74),
        .root: CGPoint(x: 0.40, y: 0.68), .rightHip: CGPoint(x: 0.40, y: 0.68),
        .rightKnee: CGPoint(x: 0.56, y: 0.70), .rightAnkle: CGPoint(x: 0.50, y: 0.88)
    ]

    static func squat(depth: Double, lean: Bool, timestamp: TimeInterval) -> Pose {
        let target = lean ? bottomLean : bottom
        let d = CGFloat(max(0, min(1, depth)))
        var points: [Joint: CGPoint] = [:]
        var confidences: [Joint: Float] = [:]
        for (joint, a) in standing {
            guard let b = target[joint] else { continue }
            let p = CGPoint(x: a.x + (b.x - a.x) * d, y: a.y + (b.y - a.y) * d)
            points[joint] = p
            confidences[joint] = 0.9
        }
        // Far (left) side sits just behind the near side.
        let mirrors: [(Joint, Joint)] = [(.rightShoulder, .leftShoulder), (.rightElbow, .leftElbow), (.rightWrist, .leftWrist),
                                         (.rightHip, .leftHip), (.rightKnee, .leftKnee), (.rightAnkle, .leftAnkle)]
        for (near, far) in mirrors {
            if let p = points[near] {
                points[far] = CGPoint(x: p.x - 0.015, y: p.y - 0.004)
                confidences[far] = 0.6
            }
        }
        return Pose(points: points, confidences: confidences, imageSize: CGSize(width: 720, height: 1280), timestamp: timestamp)
    }
}
