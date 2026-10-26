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
        await service.loadProducts()
    }

    override func tearDown() async throws {
        session?.clearTransactions()
    }

    func testProductsShowPriceAndFreeTrial() {
        XCTAssertEqual(service.products.map(\.id), [SubscriptionService.yearly, SubscriptionService.monthly])
        XCTAssertEqual(service.products.map(\.displayPrice), ["$39.99", "$4.99"])
        XCTAssertEqual(service.products.map(\.trialDays), [7, 7])
        XCTAssertEqual(service.products.map(\.isYearly), [true, false])
        XCTAssertTrue(service.isEligibleForTrial)
        XCTAssertFalse(service.hasAccess)
    }

    func testBuyingStartsTheFreeTrialAndGivesAccess() async throws {
        var gained = 0
        service.onAccessGained = { gained += 1 }
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
        await service.refresh()

        XCTAssertNil(service.entitlement)
        XCTAssertFalse(service.hasAccess)
        XCTAssertFalse(service.isEligibleForTrial)
    }

    func testAccessEndsWhenRefunded() async throws {
        let transaction = try await session.buyProduct(identifier: SubscriptionService.monthly)
        await service.refresh()
        XCTAssertTrue(service.hasAccess)

        try session.refundTransaction(identifier: UInt(transaction.id))
        await service.refresh()

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
