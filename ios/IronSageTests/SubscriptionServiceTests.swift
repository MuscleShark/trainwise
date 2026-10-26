import StoreKit
import StoreKitTest
import XCTest
@testable import IronSage

/// Buys, restores, expires and refunds IronSage Coach against `ios/IronSage.storekit`,
/// the same file the scheme uses when the app runs in the simulator.
@MainActor
final class SubscriptionServiceTests: XCTestCase {
    private var session: SKTestSession!
    private var defaults: UserDefaults!
    private var service: SubscriptionService!

    override func setUp() async throws {
        let configuration = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "IronSage.storekit")
        session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defaults = UserDefaults(suiteName: "IronSageTests.subscription")
        defaults.removePersistentDomain(forName: "IronSageTests.subscription")
        service = SubscriptionService(api: nil, defaults: defaults)
        // StoreKit's test service can take a while on a simulator that just booted (on
        // CI the first request returns no products), so ask again until it answers.
        let deadline = ContinuousClock.now + .seconds(60)
        await service.loadProducts()
        while service.products.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .seconds(1))
            await service.loadProducts()
        }
        let products = service.products
        XCTAssertFalse(products.isEmpty, "StoreKit returned no products from IronSage.storekit")
    }

    override func tearDown() async throws {
        session?.clearTransactions()
    }

    /// StoreKit's test session applies changes asynchronously: refreshes until `condition` holds.
    private func refresh(until condition: () -> Bool, timeout: Duration = .seconds(15)) async {
        let deadline = ContinuousClock.now + timeout
        await service.refresh()
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(500))
            await service.refresh()
        }
    }

    func testProductsShowPriceAndFreeTrial() async {
        XCTAssertEqual(service.products.map(\.id), [SubscriptionService.yearly, SubscriptionService.monthly])
        XCTAssertEqual(service.products.map(\.displayPrice), ["$39.99", "$4.99"])
        XCTAssertEqual(service.products.map(\.trialDays), [7, 7])
        XCTAssertEqual(service.products.map(\.isYearly), [true, false])
        await refresh { service.isEligibleForTrial }
        XCTAssertTrue(service.isEligibleForTrial)
        XCTAssertFalse(service.hasAccess)
    }

    func testTheConfigurationHasAnOfferCodeForEachPlan() throws {
        // Real codes are made in App Store Connect; these let redemption be tried locally.
        let configuration = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "IronSage.storekit")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configuration)) as? [String: Any]
        let groups = try XCTUnwrap(json?["subscriptionGroups"] as? [[String: Any]])
        let plans = try XCTUnwrap(groups.first?["subscriptions"] as? [[String: Any]])
        let codes = plans.flatMap { ($0["codeOffers"] as? [[String: Any]] ?? []).compactMap { $0["offerID"] as? String } }
        XCTAssertEqual(Set(codes), ["COACHYEAR50", "COACHMONTH50"])
    }

    func testBuyingStartsTheFreeTrialAndGivesAccess() async throws {
        var gained = 0
        service.onAccessGained = { gained += 1 }
        // The launch refresh: learning the state isn't gaining access.
        await service.refresh()
        XCTAssertEqual(gained, 0)
        let monthly = try XCTUnwrap(service.products.first { $0.id == SubscriptionService.monthly })

        let outcome = try await service.purchase(monthly)

        guard case .purchased = outcome else { return XCTFail("Expected a purchase, got \(outcome)") }
        let entitlement = try XCTUnwrap(service.entitlement)
        XCTAssertEqual(entitlement.productID, SubscriptionService.monthly)
        XCTAssertTrue(entitlement.isTrial)
        XCTAssertTrue(entitlement.willRenew)
        let trialEnd = try XCTUnwrap(entitlement.expiresAt)
        XCTAssertEqual(trialEnd.timeIntervalSinceNow, 7 * 24 * 60 * 60, accuracy: 60 * 60)
        XCTAssertTrue(service.hasAccess)
        XCTAssertFalse(service.isEligibleForTrial, "The trial is for new subscribers only")
        XCTAssertEqual(gained, 1)
    }

    func testRestoreFindsASubscriptionBoughtElsewhere() async throws {
        // Bought on another device with the same Apple Account.
        _ = try await session.buyProduct(identifier: SubscriptionService.yearly)
        let fresh = SubscriptionService(api: nil, defaults: defaults)

        try await fresh.restore()

        XCTAssertEqual(fresh.entitlement?.productID, SubscriptionService.yearly)
        XCTAssertTrue(fresh.hasAccess)
    }

    func testAccessEndsWhenTheSubscriptionExpires() async throws {
        let yearly = try XCTUnwrap(service.products.first { $0.id == SubscriptionService.yearly })
        _ = try await service.purchase(yearly)
        XCTAssertTrue(service.hasAccess)

        try session.expireSubscription(productIdentifier: SubscriptionService.yearly)
        await refresh { service.entitlement == nil }

        XCTAssertNil(service.entitlement)
        XCTAssertFalse(service.hasAccess)
        XCTAssertFalse(service.isEligibleForTrial)
    }

    func testAccessEndsWhenRefunded() async throws {
        let transaction = try await session.buyProduct(identifier: SubscriptionService.monthly)
        await service.refresh()
        XCTAssertTrue(service.hasAccess)

        try session.refundTransaction(identifier: UInt(transaction.id))
        await refresh { service.entitlement == nil }

        XCTAssertNil(service.entitlement)
    }

    func testTurningRenewalOffShowsTheEndDate() async throws {
        _ = try await session.buyProduct(identifier: SubscriptionService.monthly)
        try session.disableAutoRenewForTransaction(identifier: UInt(try XCTUnwrap(session.allTransactions().last).identifier))
        await service.refresh()

        XCTAssertEqual(service.entitlement?.willRenew, false)
        XCTAssertTrue(service.hasAccess, "Access lasts until the end of the period")
    }
}
