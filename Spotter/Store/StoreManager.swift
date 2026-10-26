import Foundation
import StoreKit

/// StoreKit 2 subscriptions for Spotter Pro.
/// Product IDs must match App Store Connect (or the bundled Spotter.storekit file for local testing).
@MainActor
final class StoreManager: ObservableObject {
    static let yearlyID = "spotter.pro.yearly"
    static let monthlyID = "spotter.pro.monthly"
    static let productIDs = [yearlyID, monthlyID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    var yearly: Product? { products.first { $0.id == Self.yearlyID } }
    var monthly: Product? { products.first { $0.id == Self.monthlyID } }

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
        } catch {
            products = []
        }
    }

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        isPro = active || UserDefaults.standard.bool(forKey: "debugPro")
        UserDefaults.standard.set(isPro, forKey: "cachedIsPro")
    }

    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        SpotterAnalytics.log("purchase_start", ["product_id": product.id])
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    SpotterAnalytics.log("purchase_success", ["product_id": product.id])
                    return true
                }
                errorMessage = String(localized: "We couldn't verify that purchase.")
                SpotterAnalytics.log("purchase_fail", ["product_id": product.id])
                return false
            case .userCancelled:
                SpotterAnalytics.log("purchase_cancel", ["product_id": product.id])
                return false
            case .pending:
                SpotterAnalytics.log("purchase_pending", ["product_id": product.id])
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            SpotterAnalytics.log("purchase_fail", ["product_id": product.id])
            return false
        }
    }

    func restore() async {
        SpotterAnalytics.log("restore_purchases")
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshEntitlements()
        SpotterAnalytics.sync(isPro: isPro)
    }

    /// Debug-only unlock so you can test Pro features before StoreKit is configured.
    func setDebugPro(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "debugPro")
        Task { await refreshEntitlements() }
    }
}
