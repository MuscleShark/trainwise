import StoreKit
import SwiftUI

/// Settings → IronSage Coach: what's free, what the subscription adds and what it
/// costs, so the price can be found without first turning the AI coach on.
struct CoachPlanView: View {
    @Environment(SubscriptionService.self) private var subscriptions
    @State private var showsPaywall = false
    @State private var managesSubscription = false

    private let free: [(String, LocalizedStringResource)] = [
        ("list.bullet.clipboard", "Log workouts, even offline"),
        ("clock.arrow.circlepath", "History, templates and records"),
        ("chart.xyaxis.line", "Progress charts and Apple Health"),
        ("figure.strengthtraining.traditional", "How to do each exercise"),
        ("checkmark.seal", "Suggested weights and reps for your next session"),
    ]

    private let paid: [(String, LocalizedStringResource)] = [
        ("text.bubble", "The reason behind each suggested weight and rep"),
        ("bed.double", "Adjustments for your sleep and recovery"),
        ("calendar", "A summary of your training every Monday"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(free, id: \.0) { feature($0, $1) }
            } header: {
                Text("Free")
            }

            Section {
                ForEach(paid, id: \.0) { feature($0, $1) }
                if let prices {
                    Text(prices)
                        .font(.subheadline.weight(.semibold))
                }
            } header: {
                Text("IronSage Coach")
                    .textCase(nil)
            } footer: {
                if subscriptions.entitlement == nil && subscriptions.isEligibleForTrial {
                    Text("New subscribers get a free trial. Cancel any time in Settings › Apple Account › Subscriptions.")
                }
            }

            Section {
                if subscriptions.entitlement != nil {
                    LabeledContent("Your plan", value: String(localized: CoachPlanRow.status(subscriptions)))
                    Button("Manage subscription") { managesSubscription = true }
                        .manageSubscriptionsSheet(isPresented: $managesSubscription)
                } else if subscriptions.serverAccess {
                    Text("Your account has the AI coach.")
                } else {
                    Button("See plans") { showsPaywall = true }
                        .sheet(isPresented: $showsPaywall) { PaywallSheet() }
                }
            }
        }
        .brandBackground()
        .navigationTitle("IronSage Coach")
        .task { await subscriptions.loadProducts() }
    }

    /// "$4.99 a month or $39.99 a year", from the App Store.
    private var prices: LocalizedStringResource? {
        let monthly = subscriptions.products.first { !$0.isYearly }
        let yearly = subscriptions.products.first { $0.isYearly }
        guard let monthly, let yearly else { return nil }
        return "\(monthly.displayPrice) a month or \(yearly.displayPrice) a year"
    }

    private func feature(_ icon: String, _ label: LocalizedStringResource) -> some View {
        Label { Text(label) } icon: { Image(systemName: icon).foregroundStyle(.tint) }
    }
}

/// The IronSage Coach row in Settings, with the current plan.
struct CoachPlanRow: View {
    @Environment(SubscriptionService.self) private var subscriptions

    var body: some View {
        LabeledContent {
            Text(Self.status(subscriptions))
        } label: {
            Label { Text("IronSage Coach") } icon: { Image(systemName: "sparkles").foregroundStyle(.tint) }
        }
    }

    static func status(_ subscriptions: SubscriptionService) -> LocalizedStringResource {
        if let entitlement = subscriptions.entitlement {
            entitlement.productID == SubscriptionService.yearly ? "Yearly" : "Monthly"
        } else if subscriptions.serverAccess {
            "Included"
        } else {
            "Free"
        }
    }
}
