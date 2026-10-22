import SwiftUI

enum Theme {
    static let bg = Color(red: 0.035, green: 0.039, blue: 0.051)
    static let surface = Color(red: 0.082, green: 0.090, blue: 0.110)
    static let surfaceHigh = Color(red: 0.122, green: 0.133, blue: 0.161)
    static let stroke = Color.white.opacity(0.08)

    /// Electric lime: the brand colour, used for "good" and primary actions.
    static let accent = Color(red: 0.776, green: 1.0, blue: 0.239)
    static let accentSoft = Color(red: 0.776, green: 1.0, blue: 0.239).opacity(0.14)
    static let violet = Color(red: 0.545, green: 0.478, blue: 1.0)
    static let warn = Color(red: 1.0, green: 0.741, blue: 0.180)
    static let bad = Color(red: 1.0, green: 0.361, blue: 0.361)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.64)
    static let textTertiary = Color.white.opacity(0.40)

    static func scoreColor(_ score: Int) -> Color {
        score >= 85 ? accent : score >= 65 ? warn : bad
    }
}

extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    func eyebrow(_ color: Color = Theme.textTertiary) -> some View {
        self.font(.system(size: 11, weight: .bold))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

// MARK: - Components

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(17, weight: .bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12)))
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke))
    }
}

struct Pill: View {
    let text: String
    var symbol: String? = nil
    var color: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.07), in: Capsule())
    }
}

struct ScoreRing: View {
    let score: Int?
    var size: CGFloat = 56
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(score ?? 0) / 100)
                .stroke(Theme.scoreColor(score ?? 0), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: score)
            Text(score.map(String.init) ?? "–")
                .font(.display(size * 0.32, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct CircleIconButton: View {
    let symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

struct SelectionRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? .black : Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(selected ? Theme.accent : Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.display(17, weight: .semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}
