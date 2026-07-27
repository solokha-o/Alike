import Foundation
import StoreKit

protocol StoreKitClient: Sendable {
    func loadProducts(ids: Set<String>) async throws -> [StorefrontProduct]
    func purchase(productID: String) async throws -> StoreKitPurchaseOutcome
    func sync() async throws
    func currentEntitlements() async throws -> [StoreKitEntitlement]
    func transactionUpdates() -> AsyncStream<StoreKitTransactionUpdate>
}

struct AppStoreKitClient: StoreKitClient {
    func loadProducts(ids: Set<String>) async throws -> [StorefrontProduct] {
        let products = try await Product.products(for: ids)
        return products.map {
            StorefrontProduct(
                id: $0.id,
                displayName: $0.displayName,
                displayPrice: $0.displayPrice,
                price: $0.price
            )
        }
    }

    func purchase(productID: String) async throws -> StoreKitPurchaseOutcome {
        guard let product = try await Product.products(for: [productID]).first else {
            throw SubscriptionStoreError.purchaseFailed("The selected subscription product is unavailable.")
        }

        switch try await product.purchase() {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                let entitlement = makeEntitlement(from: transaction, isVerified: true)
                await transaction.finish()
                return .success(entitlement)
            case .unverified(let transaction, _):
                return .success(makeEntitlement(from: transaction, isVerified: false))
            }
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func sync() async throws {
        try await AppStore.sync()
    }

    func currentEntitlements() async throws -> [StoreKitEntitlement] {
        try Task.checkCancellation()
        var entitlements: [StoreKitEntitlement] = []
        for await verification in Transaction.currentEntitlements {
            try Task.checkCancellation()
            switch verification {
            case .verified(let transaction):
                entitlements.append(makeEntitlement(from: transaction, isVerified: true))
            case .unverified(let transaction, _):
                entitlements.append(makeEntitlement(from: transaction, isVerified: false))
            }
        }
        try Task.checkCancellation()
        return entitlements
    }

    func transactionUpdates() -> AsyncStream<StoreKitTransactionUpdate> {
        AsyncStream { continuation in
            let task = Task {
                for await verification in Transaction.updates {
                    switch verification {
                    case .verified(let transaction):
                        let entitlement = makeEntitlement(from: transaction, isVerified: true)
                        await transaction.finish()
                        continuation.yield(StoreKitTransactionUpdate(entitlement: entitlement))
                    case .unverified(let transaction, _):
                        continuation.yield(
                            StoreKitTransactionUpdate(
                                entitlement: makeEntitlement(from: transaction, isVerified: false)
                            )
                        )
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeEntitlement(from transaction: Transaction, isVerified: Bool) -> StoreKitEntitlement {
        StoreKitEntitlement(
            productID: transaction.productID,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded,
            isVerified: isVerified
        )
    }
}
