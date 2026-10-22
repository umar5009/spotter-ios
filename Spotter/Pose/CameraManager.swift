import AVFoundation
import Vision
import QuartzCore
import SwiftUI

/// Lightweight publisher for the latest pose, observed only by the skeleton overlay
/// so the rest of the trainer UI doesn't re-render on every frame.
final class PoseStream: ObservableObject {
    @Published var pose: Pose?
}

/// Runs the camera and Apple Vision body-pose detection on-device.
/// No video ever leaves the phone.
final class CameraManager: NSObject, ObservableObject {
    @Published private(set) var authorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isAvailable = true
    @Published private(set) var position: AVCaptureDevice.Position = .front

    /// Called on the main thread with each processed frame's pose (nil = nobody detected).
    var onPose: ((Pose?) -> Void)?

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "spotter.camera.session")
    private let videoQueue = DispatchQueue(label: "spotter.camera.video", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var videoDevice: AVCaptureDevice?
    private var currentPosition: AVCaptureDevice.Position = .front
    private var configured = false

    /// Written on sessionQueue, read on videoQueue.
    private let orientationLock = NSLock()
    private var outputFacesFront = true

    // Touched only on videoQueue
    private let request = VNDetectHumanBodyPoseRequest()
    private var smoother = PoseSmoother()

    func requestAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .authorized
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.authorization = granted ? .authorized : .denied
                    if granted { self.start() }
                }
            }
        default:
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    func start() {
        sessionQueue.async {
            if !self.configured { self.configure() }
            guard self.configured else {
                DispatchQueue.main.async { self.isAvailable = false }
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func flipCamera() {
        sessionQueue.async {
            guard self.configured else { return }
            let newPosition: AVCaptureDevice.Position = self.currentPosition == .front ? .back : .front
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            if let old = self.input { self.session.removeInput(old) }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.input = newInput
                self.videoDevice = device
                self.currentPosition = newPosition
            } else if let old = self.input, self.session.canAddInput(old) {
                self.session.addInput(old)
            }
            self.applyConnectionSettings()
            self.session.commitConfiguration()
            let pos = self.currentPosition
            DispatchQueue.main.async { self.position = pos }
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let deviceInput = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(deviceInput) else { return }
        session.addInput(deviceInput)
        input = deviceInput
        videoDevice = device

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        applyConnectionSettings()
        configured = true
    }

    /// The phone UI is portrait and the person is standing in frame. Rotate the buffers to that
    /// orientation before Vision runs, so joint positions land on the body instead of a sideways
    /// landscape frame. Mirroring is applied first: setting it clears a rotation assigned earlier.
    private func applyConnectionSettings() {
        guard let connection = output.connection(with: .video) else { return }
        let front = currentPosition == .front
        orientationLock.lock()
        outputFacesFront = front
        orientationLock.unlock()

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = front
        }
        let angle = uprightPortraitAngle()
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    /// How far the sensor buffer must turn to stand upright in the portrait interface.
    /// A hardcoded 90° is wrong for front cameras whose sensor is already mounted in portrait:
    /// it tips an upright frame onto its side.
    private func uprightPortraitAngle() -> CGFloat {
        guard let device = videoDevice else { return 90 }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        if #available(iOS 27.0, *) {
            return coordinator.videoRotationAngleRelative(toDeviceOrientation: .portrait)
        }
        return coordinator.videoRotationAngleForHorizonLevelCapture
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let bufferSize = CGSize(width: CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
                                height: CGFloat(CVPixelBufferGetHeight(pixelBuffer)))
        orientationLock.lock()
        let front = outputFacesFront
        orientationLock.unlock()
        // If the connection rotation was applied, the buffer is already a portrait image and
        // Vision should read it upright. If it is still landscape, stand it up here so the
        // skeleton uses the same portrait frame as the camera preview.
        let (orientation, imageSize) = PoseFrame.vision(bufferSize: bufferSize,
                                                        connectionAngle: connection.videoRotationAngle,
                                                        bufferMirrored: connection.isVideoMirrored,
                                                        frontCamera: front)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do { try handler.perform([request]) } catch { return }

        // If several people are visible, coach the one with the most confidently detected joints.
        let observation = request.results?.max { a, b in
            ((try? a.recognizedPoints(.all).count) ?? 0) < ((try? b.recognizedPoints(.all).count) ?? 0)
        }
        var pose: Pose?
        if let observation {
            pose = PoseExtractor.pose(from: observation, imageSize: imageSize, timestamp: CACurrentMediaTime())
        }
        pose = smoother.smooth(pose)

        DispatchQueue.main.async { [weak self] in
            self?.onPose?(pose)
        }
    }
}

/// Maps a camera buffer onto the upright portrait image shown in the preview.
enum PoseFrame {
    static func vision(bufferSize: CGSize,
                       connectionAngle: CGFloat,
                       bufferMirrored: Bool,
                       frontCamera: Bool) -> (CGImagePropertyOrientation, CGSize) {
        // The preview mirrors the front camera. Mirror in Vision only when the buffer itself was not.
        let needsMirror = frontCamera != bufferMirrored
        if bufferSize.height >= bufferSize.width {
            return (needsMirror ? .upMirrored : .up, bufferSize)
        }

        var angle = Int(connectionAngle.rounded()) % 360
        if angle < 0 { angle += 360 }
        // Angle 0 on a landscape buffer means the connection never rotated it. A portrait
        // preview of that sensor still needs a quarter turn.
        if angle == 0 { angle = 90 }

        let orientation: CGImagePropertyOrientation
        switch angle {
        case 90:
            orientation = needsMirror ? .leftMirrored : .right
        case 180:
            orientation = needsMirror ? .downMirrored : .down
        case 270:
            orientation = needsMirror ? .rightMirrored : .left
        default:
            orientation = needsMirror ? .leftMirrored : .right
        }
        let swapsAxes = angle == 90 || angle == 270
        let imageSize = swapsAxes
            ? CGSize(width: bufferSize.height, height: bufferSize.width)
            : bufferSize
        return (orientation, imageSize)
    }
}

enum PoseExtractor {
    static let minConfidence: Float = 0.3

    static func pose(from observation: VNHumanBodyPoseObservation, imageSize: CGSize, timestamp: TimeInterval) -> Pose? {
        guard let recognized = try? observation.recognizedPoints(.all) else { return nil }
        var points: [Joint: CGPoint] = [:]
        var confidences: [Joint: Float] = [:]
        for joint in Joint.allCases {
            if let p = recognized[joint.visionName], p.confidence >= minConfidence {
                // Vision uses a bottom-left origin; flip to top-left.
                points[joint] = CGPoint(x: p.location.x, y: 1 - p.location.y)
                confidences[joint] = p.confidence
            }
        }
        guard points.count >= 4 else { return nil }
        return Pose(points: points, confidences: confidences, imageSize: imageSize, timestamp: timestamp)
    }
}

/// Exponential smoothing to remove joint jitter without adding noticeable lag.
struct PoseSmoother {
    var alpha: CGFloat = 0.6
    private var last: [Joint: CGPoint] = [:]

    mutating func smooth(_ pose: Pose?) -> Pose? {
        guard var pose else {
            last = [:]
            return nil
        }
        var smoothed: [Joint: CGPoint] = [:]
        for (joint, p) in pose.points {
            if let prev = last[joint] {
                smoothed[joint] = CGPoint(x: prev.x + alpha * (p.x - prev.x), y: prev.y + alpha * (p.y - prev.y))
            } else {
                smoothed[joint] = p
            }
        }
        last = smoothed
        pose.points = smoothed
        return pose
    }
}
