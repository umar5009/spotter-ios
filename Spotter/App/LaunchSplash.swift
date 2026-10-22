import SwiftUI

/// Continues the static launch screen. The first frame matches it, then the mark breathes, a ring expands, and the splash fades into the app.
struct LaunchSplash: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = 0.0
    @State private var scale = 1.0
    @State private var ringScale = 0.86
    @State private var ringOpacity = 0.0
    @State private var underline = false
    @State private var cover = 1.0
    @State private var lift = 1.0
    @State private var didFinish = false

    var body: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0)],
                                center: .center,
                                startRadius: 8,
                                endRadius: 110
                            )
                        )
                        .frame(width: 220, height: 220)
                        .opacity(glow)
                    Circle()
                        .stroke(Theme.accent.opacity(0.9), lineWidth: 1.5)
                        .frame(width: 132, height: 132)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                    Image("LaunchMark")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 148, height: 148)
                        .scaleEffect(scale)
                }
                .frame(width: 148, height: 148)

                Text("Spotter")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.white)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: underline ? 32 : 0, height: 3)
                            .offset(y: 12)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .scaleEffect(lift)
        .opacity(cover)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spotter")
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            finish()
            return
        }

        withAnimation(.easeOut(duration: 0.7)) { glow = 1 }
        withAnimation(.spring(response: 0.58, dampingFraction: 0.55).delay(0.05)) { scale = 1.08 }

        try? await Task.sleep(nanoseconds: 280_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.35)) { underline = true }
        withAnimation(.easeOut(duration: 0.16)) { ringOpacity = 0.85 }
        withAnimation(.easeOut(duration: 0.85)) { ringScale = 2.15 }

        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: 0.55)) { ringOpacity = 0 }

        try? await Task.sleep(nanoseconds: 260_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { scale = 1 }

        try? await Task.sleep(nanoseconds: 280_000_000)
        guard !Task.isCancelled else { return }
        finish()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        withAnimation(.easeInOut(duration: 0.38)) {
            cover = 0
            lift = 1.04
        } completion: {
            onFinished()
        }
    }
}
