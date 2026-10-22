import Foundation
import CoreGraphics
import Vision

/// The body joints Spotter tracks (a subset of Apple Vision's 19-point body model).
enum Joint: String, CaseIterable, Hashable {
    case nose, neck
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case root
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle

    var visionName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .nose: return .nose
        case .neck: return .neck
        case .leftShoulder: return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftElbow: return .leftElbow
        case .rightElbow: return .rightElbow
        case .leftWrist: return .leftWrist
        case .rightWrist: return .rightWrist
        case .root: return .root
        case .leftHip: return .leftHip
        case .rightHip: return .rightHip
        case .leftKnee: return .leftKnee
        case .rightKnee: return .rightKnee
        case .leftAnkle: return .leftAnkle
        case .rightAnkle: return .rightAnkle
        }
    }
}

enum Side {
    case left, right

    var opposite: Side { self == .left ? .right : .left }
    var shoulder: Joint { self == .left ? .leftShoulder : .rightShoulder }
    var elbow: Joint { self == .left ? .leftElbow : .rightElbow }
    var wrist: Joint { self == .left ? .leftWrist : .rightWrist }
    var hip: Joint { self == .left ? .leftHip : .rightHip }
    var knee: Joint { self == .left ? .leftKnee : .rightKnee }
    var ankle: Joint { self == .left ? .leftAnkle : .rightAnkle }
}

/// A side-independent joint, resolved to a concrete joint once we know which side faces the camera.
enum JointRole: CaseIterable {
    case shoulder, elbow, wrist, hip, knee, ankle

    func joint(_ side: Side) -> Joint {
        switch self {
        case .shoulder: return side.shoulder
        case .elbow: return side.elbow
        case .wrist: return side.wrist
        case .hip: return side.hip
        case .knee: return side.knee
        case .ankle: return side.ankle
        }
    }
}

/// One detected body pose.
/// `points` are normalized (0...1) with a top-left origin, in the coordinate space of the
/// upright (and, for the front camera, mirrored) video frame — i.e. exactly what the user sees.
struct Pose {
    var points: [Joint: CGPoint]
    var confidences: [Joint: Float]
    var imageSize: CGSize
    var timestamp: TimeInterval

    func has(_ joint: Joint) -> Bool { points[joint] != nil }

    /// Joint position in pixel space. Use this for any geometry so angles are not distorted
    /// by the non-square frame.
    func px(_ joint: Joint) -> CGPoint? {
        guard let p = points[joint] else { return nil }
        return CGPoint(x: p.x * imageSize.width, y: p.y * imageSize.height)
    }

    func sideConfidence(_ side: Side) -> Float {
        JointRole.allCases.reduce(Float(0)) { $0 + (confidences[$1.joint(side)] ?? 0) }
    }

    /// The side of the body most visible to the camera.
    var bestSide: Side { sideConfidence(.left) >= sideConfidence(.right) ? .left : .right }

    static let bones: [(Joint, Joint)] = [
        (.nose, .neck),
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]
}
