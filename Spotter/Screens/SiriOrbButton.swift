import SwiftUI

/// Floating coach button. Colors orbit inside the circle the way the Siri orb does.
struct SiriOrbButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                SiriOrb(time: context.date.timeIntervalSinceReferenceDate)
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(OrbPressStyle())
        .accessibilityLabel("Coach")
    }
}

private struct OrbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct SiriOrb: View {
    var time: TimeInterval

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.05, green: 0.06, blue: 0.12))
            blob(Color(red: 0.15, green: 0.55, blue: 1), speed: 0.9, phase: 0.2, distance: 12, diameter: 36)
            blob(Color(red: 0.48, green: 0.25, blue: 1), speed: -0.75, phase: 1.5, distance: 10, diameter: 38)
            blob(Color(red: 1, green: 0.28, blue: 0.55), speed: 1.0, phase: 2.7, distance: 13, diameter: 30)
            blob(Color(red: 0.1, green: 0.85, blue: 0.75), speed: -0.6, phase: 3.6, distance: 11, diameter: 28)
            blob(Theme.accent, speed: 0.7, phase: 4.5, distance: 9, diameter: 24)
        }
        .clipShape(Circle())
    }

    private func blob(_ color: Color, speed: Double, phase: Double, distance: CGFloat, diameter: CGFloat) -> some View {
        let angle = time * speed + phase
        return Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .offset(x: cos(angle) * distance, y: sin(angle) * distance)
    }
}
