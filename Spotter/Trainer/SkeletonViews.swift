import SwiftUI
import AVFoundation

/// Live camera feed.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Draws the tracked skeleton. Joints involved in a form fault turn red.
struct SkeletonCanvas: View {
    let pose: Pose?
    var faultJoints: Set<Joint> = []
    var tint: Color = Theme.accent

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }

            func point(_ joint: Joint) -> CGPoint? {
                guard let p = pose.points[joint] else { return nil }
                return Self.map(p, image: pose.imageSize, view: size)
            }

            var bones: [(Path, Bool)] = []
            for (a, b) in Pose.bones {
                guard let pa = point(a), let pb = point(b) else { continue }
                var path = Path()
                path.move(to: pa)
                path.addLine(to: pb)
                bones.append((path, faultJoints.contains(a) || faultJoints.contains(b)))
            }

            // Soft glow
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 9))
                for (path, bad) in bones {
                    layer.stroke(path, with: .color((bad ? Theme.bad : tint).opacity(0.75)),
                                 style: StrokeStyle(lineWidth: 12, lineCap: .round))
                }
            }
            // Crisp bones
            for (path, bad) in bones {
                context.stroke(path, with: .color(bad ? Theme.bad : tint),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            // Joints
            for joint in Joint.allCases where joint != .root && joint != .neck {
                guard let p = point(joint) else { continue }
                let bad = faultJoints.contains(joint)
                let r: CGFloat = bad ? 10 : 7
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                if bad {
                    let halo = rect.insetBy(dx: -8, dy: -8)
                    context.fill(Path(ellipseIn: halo), with: .color(Theme.bad.opacity(0.25)))
                }
                context.fill(Path(ellipseIn: rect), with: .color(Theme.bg))
                context.stroke(Path(ellipseIn: rect), with: .color(bad ? Theme.bad : .white), lineWidth: 3)
            }
        }
    }

    /// Maps a normalized image point to view space for an aspect-fill presentation.
    static func map(_ p: CGPoint, image: CGSize, view: CGSize) -> CGPoint {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = max(view.width / image.width, view.height / image.height)
        let w = image.width * scale
        let h = image.height * scale
        return CGPoint(x: (view.width - w) / 2 + p.x * w, y: (view.height - h) / 2 + p.y * h)
    }
}

/// Observes the per-frame pose stream so only the skeleton redraws at camera frame rate.
struct SkeletonLayer: View {
    @ObservedObject var stream: PoseStream
    let faultJoints: Set<Joint>
    let active: Bool

    var body: some View {
        SkeletonCanvas(pose: stream.pose, faultJoints: faultJoints, tint: active ? Theme.accent : .white.opacity(0.85))
    }
}

/// Vertical range-of-motion meter.
struct DepthBar: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 8) {
            Text("RANGE").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(.white.opacity(0.7))
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(progress >= 0.99 ? Theme.accent : Color.white.opacity(0.85))
                        .frame(height: max(10, geo.size.height * progress))
                        .animation(.easeOut(duration: 0.12), value: progress)
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 18, height: 2)
                        .offset(y: -geo.size.height + 1)
                }
            }
            .frame(width: 10)
        }
    }
}

/// Dark backdrop used for the simulator demo (no camera).
struct DemoBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.14), Theme.bg], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                Path { path in
                    let step: CGFloat = 36
                    var x: CGFloat = 0
                    while x < geo.size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height)); x += step }
                    var y: CGFloat = 0
                    while y < geo.size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geo.size.width, y: y)); y += step }
                }
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
            }
        }
    }
}
