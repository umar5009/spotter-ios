import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedYearly = true
    @State private var showClose = false

    private let benefits: [(String, String, String)] = [
        ("camera.viewfinder", "Live form correction", "Every exercise, with real-time cues as you move"),
        ("dumbbell.fill", "Gym mode", "Bench, rows, hip thrusts, presses and curls, with the load remembered"),
        ("chart.line.uptrend.xyaxis", "Your personal plan", "Change today's workout, at home or in the gym"),
        ("target", "Your #1 fix", "The next session watches the fault from last time")
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Spotter Pro").eyebrow(Theme.accent)
                        Text("Train with a coach that never misses a rep.")
                            .font(.display(32, weight: .heavy))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Less than one personal-training session, for a whole year.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 48)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(benefits, id: \.1) { symbol, title, text in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: symbol)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title).font(.display(16, weight: .bold)).foregroundStyle(.white)
                                    Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        planCard(yearly: true)
                        planCard(yearly: false)
                    }

                    Button {
                        let plan = selectedYearly ? "yearly" : "monthly"
                        SpotterAnalytics.click("paywall_subscribe", screen: "paywall", ["plan": plan])
                        Task { await buy() }
                    } label: {
                        if store.isPurchasing {
                            ProgressView().tint(.black)
                        } else {
                            Text(ctaTitle)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(store.isPurchasing)

                    VStack(spacing: 8) {
                        Text(selectedYearly
                             ? String(localized: "7 days free, then \(price(yearly: true))/year. Cancel anytime in Settings.")
                             : String(localized: "\(price(yearly: false))/month. Cancel anytime in Settings."))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 18) {
                            Button("Restore") {
                                SpotterAnalytics.click("paywall_restore", screen: "paywall")
                                Task { await store.restore(); if store.isPro { dismiss() } }
                            }
                            Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                                .trackClick("paywall_terms", screen: "paywall")
                            Link("Privacy", destination: URL(string: "https://example.com/privacy")!)
                                .trackClick("paywall_privacy", screen: "paywall")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            if showClose {
                Button {
                    SpotterAnalytics.click("paywall_close", screen: "paywall")
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .padding(16)
                .transition(.opacity)
            }
        }
        .onAppear {
            SpotterAnalytics.log("paywall_view")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { showClose = true } }
        }
        .alert("Purchase", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { SpotterAnalytics.click("paywall_error_ok", screen: "paywall") }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var ctaTitle: String {
        selectedYearly ? String(localized: "Start 7-day free trial") : String(localized: "Subscribe monthly")
    }

    private func price(yearly: Bool) -> String {
        if let product = yearly ? store.yearly : store.monthly { return product.displayPrice }
        return yearly ? "$39.99" : "$9.99"
    }

    private func perMonth() -> String {
        if let yearly = store.yearly {
            let monthly = yearly.price / 12
            return monthly.formatted(yearly.priceFormatStyle)
        }
        return "$3.33"
    }

    private func planCard(yearly: Bool) -> some View {
        let selected = selectedYearly == yearly
        return Button {
            SpotterAnalytics.click("paywall_plan", screen: "paywall", ["plan": yearly ? "yearly" : "monthly"])
            selectedYearly = yearly
            Haptics.tap()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(yearly ? String(localized: "Yearly") : String(localized: "Monthly")).font(.display(17, weight: .bold)).foregroundStyle(.white)
                        if yearly {
                            Text("SAVE 66%")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.accent, in: Capsule())
                        }
                    }
                    Text(yearly
                         ? String(localized: "7-day free trial · \(perMonth())/mo")
                         : String(localized: "Billed monthly"))
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(price(yearly: yearly)).font(.display(17, weight: .bold)).foregroundStyle(.white)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func buy() async {
        guard let product = selectedYearly ? store.yearly : store.monthly else {
            #if DEBUG
            store.setDebugPro(true)
            dismiss()
            #else
            store.errorMessage = String(localized: "The store isn't available right now. Please try again later.")
            #endif
            return
        }
        if await store.purchase(product) { dismiss() }
    }
}
