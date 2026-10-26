import Foundation
import IronSageAPI
import OSLog
import StoreKit

private let log = Logger(subsystem: "app.ironsage.IronSage", category: "subscription")

/// The IronSage Coach subscription (StoreKit 2), which pays for the AI coach.
///
/// The App Store is the source of truth on the phone: `Transaction.currentEntitlements`
/// says whether this Apple Account is subscribed, and `Transaction.updates` brings
/// renewals, refunds and purchases made elsewhere. Every verified transaction is also
/// sent to the API (PUT /v1/subscription), which checks Apple's signature itself and
/// is what actually lets the coach answer. The rule-based suggestions stay free.
///
/// In the simulator, purchases go to `ios/IronSage.storekit` (set in the scheme), so
/// buying, the free trial, renewals, refunds and expiry can be tried without an
/// Apple Developer account: Debug › StoreKit › Manage Transactions in Xcode.
@MainActor
@Observable
final class SubscriptionService {
    static let groupName = "IronSage Coach"
    static let yearly = "app.ironsage.coach.yearly"
    static let monthly = "app.ironsage.coach.monthly"
    static let productIDs = [yearly, monthly]

    struct Entitlement: Equatable {
        let productID: String
        let expiresAt: Date?
        /// In the free trial.
        let isTrial: Bool
        /// Renews at `expiresAt`; false once the subscriber turned renewal off.
        let willRenew: Bool
    }

    enum PurchaseOutcome {
        case purchased
        /// Waiting for approval (Ask to Buy) or a payment problem to be fixed.
        case pending
        case cancelled
    }

    /// Yearly first, then monthly; empty until loaded or when the App Store can't be reached.
    private(set) var products: [Product] = []
    private(set) var entitlement: Entitlement?
    /// A new subscriber gets the free trial; someone who had one before doesn't.
    private(set) var isEligibleForTrial = true
    /// The server allows this account the coach: a subscription it verified, or a test
    /// account allowed by hand.
    private(set) var serverAccess = false
    /// This Apple Account's subscription is linked to another IronSage account.
    private(set) var isLinkedElsewhere = false

    /// Subscribed on this Apple Account and linked to this IronSage account, or allowed by the server.
    var hasAccess: Bool {
        (entitlement != nil && !isLinkedElsewhere) || serverAccess
    }

    /// Called when the account gains access, for example after a purchase, a restore or
    /// an Ask to Buy approval, so the coach asks again.
    @ObservationIgnored var onAccessGained: @MainActor () -> Void = {}

    @ObservationIgnored private let api: (any APIProtocol)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updates: Task<Void, Never>?

    private enum Keys {
        /// The last transaction the server accepted, so it isn't sent on every launch.
        static let sent = "IronSage.subscription.sent"
    }

    /// `api` is nil in demo mode: nothing is sent.
    init(api: (any APIProtocol)?, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    // MARK: Products

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { Self.productIDs.firstIndex(of: $0.id)! < Self.productIDs.firstIndex(of: $1.id)! }
            if let subscription = products.first?.subscription {
                isEligibleForTrial = await subscription.isEligibleForIntroOffer
            }
        } catch {
            log.error("Loading products failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Buying

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        switch try await product.purchase() {
        case .success(let result):
            let transaction = try result.payloadValue
            await send(result.jwsRepresentation, transactionID: transaction.id)
            await transaction.finish()
            await refresh()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Restore purchases: asks the App Store for this Apple Account's transactions (it may
    /// ask the user to sign in) and sends the current one to the server again.
    func restore() async throws {
        try await AppStore.sync()
        defaults.removeObject(forKey: Keys.sent)
        await refresh()
    }

    // MARK: State

    /// Reads the current entitlement and makes sure the server has it. Call it at launch
    /// and when the app comes to the foreground.
    func refresh() async {
        let hadAccess = hasAccess
        defer {
            if !hadAccess && hasAccess {
                onAccessGained()
            }
        }
        var latest: (entitlement: Entitlement, jws: String, id: UInt64)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            if let current = latest?.entitlement.expiresAt, let expires = transaction.expirationDate, expires <= current {
                continue
            }
            var willRenew = true
            if case .verified(let renewal)? = await transaction.subscriptionStatus?.renewalInfo {
                willRenew = renewal.willAutoRenew
            }
            let entitlement = Entitlement(
                productID: transaction.productID,
                expiresAt: transaction.expirationDate,
                isTrial: transaction.offer?.type == .introductory,
                willRenew: willRenew
            )
            latest = (entitlement, result.jwsRepresentation, transaction.id)
        }
        entitlement = latest?.entitlement
        if let latest {
            await send(latest.jws, transactionID: latest.id)
        }
        if let subscription = products.first?.subscription {
            isEligibleForTrial = await subscription.isEligibleForIntroOffer
        }
        await refreshServerAccess()
    }

    /// Signing out or switching accounts: the next account sends its own.
    func reset() {
        serverAccess = false
        isLinkedElsewhere = false
        defaults.removeObject(forKey: Keys.sent)
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            log.error("Ignoring an unverified transaction")
            return
        }
        if Self.productIDs.contains(transaction.productID) {
            await send(result.jwsRepresentation, transactionID: transaction.id)
        }
        await transaction.finish()
        await refresh()
    }

    // MARK: Server

    private func send(_ jws: String, transactionID: UInt64) async {
        guard let api, defaults.string(forKey: Keys.sent) != String(transactionID) else { return }
        do {
            switch try await api.putSubscription(body: .json(.init(signedTransaction: jws))) {
            case .ok(let ok):
                let read = try ok.body.json
                serverAccess = read.coachAccess
                isLinkedElsewhere = false
                defaults.set(String(transactionID), forKey: Keys.sent)
            case .undocumented(statusCode: 409, _):
                isLinkedElsewhere = true
            case .unprocessableContent:
                log.error("The server refused the transaction as invalid")
            case .undocumented(let status, _):
                log.error("Sending the transaction failed with \(status)")
            }
        } catch {
            // Offline or signed out: sent again with the next refresh.
            log.error("Sending the transaction failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func refreshServerAccess() async {
        guard let api else { return }
        do {
            if case .ok(let ok) = try await api.getSubscription() {
                serverAccess = try ok.body.json.coachAccess
            }
        } catch {
            log.error("Reading the subscription failed: \(String(describing: error), privacy: .public)")
        }
    }
}

extension Product {
    /// The free trial's length in days, if the product has one.
    var trialDays: Int? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }

    var isYearly: Bool {
        subscription?.subscriptionPeriod.unit == .year
    }
}
