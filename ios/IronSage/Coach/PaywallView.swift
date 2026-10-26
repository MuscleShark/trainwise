import StoreKit
import SwiftUI

/// The IronSage Coach subscription offer. Shows the price, the free trial and how
/// renewal works before the purchase (App Store Review Guideline 3.1.2), with Restore
/// purchases and links to the terms and the privacy policy.
struct PaywallView: View {
    /// Runs after a purchase or restore that gave access.
    var onSubscribed: () -> Void = {}

    @Environment(SubscriptionService.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = SubscriptionService.yearly
    @State private var isWorking = false
    @State private var message: LocalizedStringResource?
    @State private var redeemsCode = false

    /// Apple's standard license agreement, used instead of a custom EULA.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private let features: [(String, LocalizedStringResource)] = [
        ("text.bubble", "The reason behind each suggested weight and rep"),
        ("bed.double", "Adjustments for your sleep and recovery"),
        ("checkmark.seal", "Rule-based suggestions stay free"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("IronSage Coach")
                    .font(.largeTitle.weight(.bold))
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(features, id: \.0) { icon, label in
                        Label { Text(label) } icon: { Image(systemName: icon).foregroundStyle(.tint).frame(width: 28) }
                    }
                }
                if subscriptions.products.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 10) {
                        ForEach(subscriptions.products) { product in
                            option(product)
                        }
                    }
                }
                if let selected {
                    Text(terms(for: selected))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    Link("Terms of Use", destination: Self.termsOfUse)
                    Link("Privacy policy", destination: Site.page("privacy"))
                }
                .font(.footnote)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    Task { await buy() }
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text(buttonTitle)
                    }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(selected == nil || isWorking)
                HStack(spacing: 24) {
                    Button("Restore purchases") {
                        Task { await restore() }
                    }
                    Button("Redeem code") {
                        redeemsCode = true
                    }
                }
                .disabled(isWorking)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .background(Color.appBackground)
        }
        .background(Color.appBackground)
        .task { await subscriptions.loadProducts() }
        // A redeemed offer code arrives as a transaction through Transaction.updates,
        // which SubscriptionService sends to the server like any purchase.
        .offerCodeRedemption(isPresented: $redeemsCode) { result in
            Task { await redeemed(result) }
        }
        .alert(
            Text(message ?? ""),
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private var selected: Product? {
        subscriptions.products.first { $0.id == selectedID } ?? subscriptions.products.first
    }

    private var trialDays: Int? {
        subscriptions.isEligibleForTrial ? selected?.trialDays : nil
    }

    private var buttonTitle: LocalizedStringKey {
        if let trialDays {
            "Start \(trialDays)-day free trial"
        } else {
            "Subscribe"
        }
    }

    private func option(_ product: Product) -> some View {
        let isSelected = product.id == selected?.id
        return Button {
            selectedID = product.id
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.isYearly ? LocalizedStringKey("Yearly") : "Monthly")
                        .font(.headline)
                    if product.isYearly {
                        Text("\((product.price / 12).formatted(product.priceFormatStyle)) a month, billed yearly")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(product.isYearly ? LocalizedStringKey("\(product.displayPrice)/year") : "\(product.displayPrice)/month")
                    .font(.headline)
            }
            .foregroundStyle(Color.primary)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The price, trial and renewal terms, in the words App Review expects.
    private func terms(for product: Product) -> LocalizedStringResource {
        let price = product.displayPrice
        switch (trialDays, product.isYearly) {
        case (let days?, true):
            return "Free for \(days) days, then \(price) a year. Payment is charged to your Apple Account when the trial ends. The subscription renews every year at the same price unless you turn it off at least 24 hours before the end of the current period. Manage or cancel it in Settings › Apple Account › Subscriptions."
        case (let days?, false):
            return "Free for \(days) days, then \(price) a month. Payment is charged to your Apple Account when the trial ends. The subscription renews every month at the same price unless you turn it off at least 24 hours before the end of the current period. Manage or cancel it in Settings › Apple Account › Subscriptions."
        case (nil, true):
            return "\(price) a year, charged to your Apple Account when you confirm. The subscription renews every year at the same price unless you turn it off at least 24 hours before the end of the current period. Manage or cancel it in Settings › Apple Account › Subscriptions."
        case (nil, false):
            return "\(price) a month, charged to your Apple Account when you confirm. The subscription renews every month at the same price unless you turn it off at least 24 hours before the end of the current period. Manage or cancel it in Settings › Apple Account › Subscriptions."
        }
    }

    private func buy() async {
        guard let selected else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await subscriptions.purchase(selected) {
            case .purchased:
                finish()
            case .pending:
                message = "Your purchase is waiting for approval. The AI coach turns on once it goes through."
            case .cancelled:
                break
            }
        } catch {
            message = "The purchase didn't go through. Please try again."
        }
    }

    private func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await subscriptions.restore()
        } catch StoreKitError.userCancelled {
            return
        } catch {
            message = "Couldn't reach the App Store. Check your connection and try again."
            return
        }
        if subscriptions.hasAccess || subscriptions.isLinkedElsewhere {
            finish()
        } else if subscriptions.needsConfirmation {
            message = "Your subscription was found but couldn't be confirmed with IronSage yet. Check your connection and try again."
        } else {
            message = "No IronSage Coach subscription was found for this Apple Account."
        }
    }

    private func redeemed(_ result: Result<Void, any Error>) async {
        guard case .success = result else {
            message = "The code couldn't be redeemed. Check it and try again."
            return
        }
        await subscriptions.refresh()
        if subscriptions.hasAccess {
            finish()
        }
    }

    private func finish() {
        if subscriptions.isLinkedElsewhere && !subscriptions.hasAccess {
            message = "This subscription is already linked to another IronSage account. Sign in with that account to use it."
            return
        }
        onSubscribed()
        dismiss()
    }
}
