import SwiftUI

/// The free-exercise list used on first launch to choose two coached movements.
struct FreeCoachingList: View {
    @Binding var selected: [String]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(ExerciseLibrary.free) { spec in
                SelectionRow(
                    title: spec.name,
                    subtitle: spec.muscles.joined(separator: " · "),
                    symbol: spec.symbol,
                    selected: selected.contains(spec.id)
                ) {
                    toggle(spec.id)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        Haptics.tap()
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else if selected.count < FreeCoaching.limit {
            selected.append(id)
        } else {
            Haptics.warning()
        }
    }
}

/// Shown once for people who finished onboarding before coaching picks existed.
struct FreeCoachingSetupView: View {
    var onDone: () -> Void
    @State private var selected: [String] = FreeCoaching.orderedIDs

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick 2 exercises for free coaching")
                        .font(.display(30, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.top, 24)
                    Text("Live form coaching stays free on these two. Every other exercise still counts your reps. Goal programs are part of Spotter Pro.")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 10)
                    FreeCoachingList(selected: $selected)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            Button(selected.count == FreeCoaching.limit ? String(localized: "Continue") : String(localized: "Choose 2 exercises")) {
                guard selected.count == FreeCoaching.limit else {
                    Haptics.warning()
                    return
                }
                FreeCoaching.save(selected)
                SpotterAnalytics.click("free_coaching_pick", screen: "coaching_setup", ["exercises": selected.joined(separator: ",")])
                Haptics.tap()
                onDone()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
