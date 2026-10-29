import SwiftUI
import AVFoundation

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var step = 0
    @State private var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

    /// Welcome, camera, then badges. Plan choices stay in Settings.
    private let lastStep = 2

    var body: some View {
        VStack(spacing: 0) {
            if step > 0 {
                HStack(spacing: 14) {
                    Button {
                        SpotterAnalytics.click("onboarding_back", screen: "onboarding", ["step": step])
                        withAnimation { step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    }
                    ProgressView(value: Double(step), total: Double(lastStep))
                        .tint(Theme.accent)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            Group {
                switch step {
                case 0: welcome
                case 1: cameraStep
                default: badgesStep
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            Spacer(minLength: 0)

            Button(buttonTitle) { advance() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var buttonTitle: String {
        switch step {
        case 0: return String(localized: "Get started")
        case 1: return cameraGranted ? String(localized: "Continue") : String(localized: "Allow camera")
        default: return String(localized: "Go to Home")
        }
    }

    private func advance() {
        Haptics.tap()
        SpotterAnalytics.click("onboarding_continue", screen: "onboarding", ["step": step])
        if step == 1 && !cameraGranted {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraGranted = granted
                    withAnimation { step += 1 }
                }
            }
            return
        }
        if step >= lastStep {
            onFinish()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { step += 1 }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            AnimatedCoachPreview()
                .frame(height: 380)
                .padding(.top, 12)
            VStack(alignment: .leading, spacing: 10) {
                Text("No gym needed. No guesswork.").eyebrow(Theme.accent)
                Text("A personal trainer that watches every rep.")
                    .font(.display(34, weight: .heavy))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Prop up your phone. Spotter counts your reps, scores your form and tells you how to fix it out loud, as you move.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
    }

    private var cameraStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How your AI coach sees you").font(.display(30, weight: .heavy)).foregroundStyle(.white).padding(.top, 24)
            feature("iphone.gen3", "Prop your phone up", "Against a wall or water bottle, 2 to 3 metres away.")
            feature("figure.stand", "Step into frame", "Spotter tracks 15 points on your body in real time.")
            feature("waveform", "Listen and adjust", "Hear rep counts and corrections like “Keep your chest up.”")
            feature("lock.shield.fill", "Private by design", "Everything runs on your iPhone. No video is recorded or uploaded.")
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var badgesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How you earn badges").font(.display(30, weight: .heavy)).foregroundStyle(.white).padding(.top, 24)
                Text("Progress recounts your saved workouts and weigh-ins. A badge stays once you qualify, even if a streak breaks.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(SpotterBadge.allCases) { badge in
                    badgeRow(badge)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private func badgeRow(_ badge: SpotterBadge) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: badge.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(badge.title).font(.display(17, weight: .bold)).foregroundStyle(.white)
                Text(badge.requirement).font(.subheadline).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.display(17, weight: .bold)).foregroundStyle(.white)
                Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Looping animated skeleton with live cues, used as the onboarding hero.
struct AnimatedCoachPreview: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let cycle = t.truncatingRemainder(dividingBy: 6.0)
            let depth = (1 - cos(t * 2 * .pi / 3.0)) / 2
            let leaning = cycle > 3.0
            let pose = DemoPoseSource.squat(depth: depth, lean: leaning, timestamp: t)
            let fault: Set<Joint> = leaning && depth > 0.7 ? [.rightShoulder, .rightHip] : []

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.surfaceHigh, Theme.surface], startPoint: .top, endPoint: .bottom))
                SkeletonCanvas(pose: pose, faultJoints: fault)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                HStack {
                    Pill(text: fault.isEmpty ? "Great depth" : "Keep your chest up",
                         symbol: fault.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                         color: fault.isEmpty ? Theme.accent : Theme.bad)
                    Spacer()
                    Text("\(Int(t / 3.0) % 12 + 1) reps")
                        .font(.display(15, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                }
                .padding(16)
            }
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Theme.stroke))
        }
    }
}
