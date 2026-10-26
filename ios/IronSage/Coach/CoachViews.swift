import IronSageCore
import IronSageStore
import StoreKit
import SwiftUI

/// Asked before anything is sent to the AI coach (docs/consent-copy.md, section 3).
/// Without a subscription it continues to the paywall, and the coach turns on once
/// the purchase goes through.
struct CoachConsentView: View {
    @Environment(CoachService.self) private var coach
    @Environment(SubscriptionService.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @State private var showsPaywall = false

    private let sent: [(String, LocalizedStringResource)] = [
        ("dumbbell", "Your recent sets for the exercises in the suggestion"),
        ("person.text.rectangle", "Your experience, goal and units"),
        ("bed.double", "Daily summaries of sleep, heart rate variability and resting heart rate"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Turn on the AI coach?")
                        .font(.largeTitle.weight(.bold))
                    Text("To suggest your next weights and reps, IronSage sends this to Anthropic, the company that makes the Claude AI model:")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(sent, id: \.0) { icon, label in
                            Label { Text(label) } icon: { Image(systemName: icon).foregroundStyle(.tint).frame(width: 28) }
                        }
                    }
                    Text("Your name and email address are never sent.")
                    Text("Every suggestion shows the data it used. You can turn the AI coach off in Settings at any time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !subscriptions.hasAccess {
                        Text("The AI coach comes with IronSage Coach, a subscription with a free trial for new subscribers.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Link("Privacy policy", destination: Site.page("privacy"))
                        .font(.footnote)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if subscriptions.hasAccess {
                        Button("Turn on AI coach") {
                            coach.turnOn()
                            dismiss()
                        }
                        .buttonStyle(BrandPrimaryButtonStyle())
                    } else {
                        Button("Continue") {
                            showsPaywall = true
                        }
                        .buttonStyle(BrandPrimaryButtonStyle())
                    }
                    Button("Not now") {
                        coach.notNow()
                        dismiss()
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .background(Color.appBackground)
            }
            .background(Color.appBackground)
            .navigationDestination(isPresented: $showsPaywall) {
                PaywallView {
                    coach.turnOn()
                    dismiss()
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

/// The paywall on its own, from places where the coach is already on.
struct PaywallSheet: View {
    @Environment(CoachService.self) private var coach
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PaywallView { coach.accessGained() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Not now") { dismiss() }
                    }
                }
        }
    }
}

/// The coach's part of the Up next card: an offer to turn it on, its progress, or its
/// summary. The per-exercise reasons are shown by `UpNextSection` under each exercise.
struct CoachUpNextRow: View {
    let recommendation: Recommendation?
    @Environment(CoachService.self) private var coach
    @Environment(SubscriptionService.self) private var subscriptions
    @State private var isAsking = false
    @State private var showsPaywall = false

    var body: some View {
        Group {
            if coach.isEnabled && coach.isUnavailable && !subscriptions.hasAccess {
                Button {
                    showsPaywall = true
                } label: {
                    Label("Subscribe to IronSage Coach for the AI coach's take", systemImage: "sparkles")
                }
            } else if !coach.isEnabled {
                if !coach.hasDecided && !coach.isUnavailable {
                    Button {
                        isAsking = true
                    } label: {
                        Label("Get the AI coach's take on this session", systemImage: "sparkles")
                    }
                }
            } else if let recommendation {
                if recommendation.isWaiting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("The AI coach is looking at your plan…")
                            .foregroundStyle(.secondary)
                    }
                } else if let advice = recommendation.output {
                    NavigationLink(value: CoachRoute(id: recommendation.id)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(advice.summary)
                                    .foregroundStyle(Color.primary)
                                Text("What the AI coach used")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        } icon: {
                            Image(systemName: "sparkles").foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .font(.subheadline)
        .sheet(isPresented: $isAsking) { CoachConsentView() }
        .sheet(isPresented: $showsPaywall) { PaywallSheet() }
    }
}

struct CoachRoute: Hashable {
    let id: UUID
}

/// What one suggestion was based on: the data sent and the coach's answer.
struct CoachDataView: View {
    let id: UUID
    @Environment(LocalStore.self) private var store

    var body: some View {
        let unit = store.weightUnit
        let recommendation = store.recommendations.first { $0.id == id }
        List {
            if let advice = recommendation?.output {
                Section {
                    Text(advice.summary)
                } footer: {
                    Text("Training guidance, not medical advice. Stop if something hurts.")
                }
            }
            if let request = recommendation?.request {
                let readiness = request.readiness
                if readiness.sleepMinutes != nil || readiness.hrvMs != nil || readiness.restingHrBpm != nil {
                    Section("Last night") {
                        if let sleep = readiness.sleepMinutes {
                            row("Sleep", value: ReadinessCard.duration(sleep.value), usual: sleep.usual.map(ReadinessCard.duration))
                        }
                        if let hrv = readiness.hrvMs {
                            row("HRV", value: ReadinessCard.milliseconds(hrv.value), usual: hrv.usual.map(ReadinessCard.milliseconds))
                        }
                        if let resting = readiness.restingHrBpm {
                            row("Resting heart rate", value: ReadinessCard.beats(resting.value), usual: resting.usual.map(ReadinessCard.beats))
                        }
                    }
                }
                ForEach(Array(request.exercises.enumerated()), id: \.offset) { _, plan in
                    Section(plan.name) {
                        if let advice = recommendation?.output?.exercises.first(where: { $0.exerciseId == plan.exerciseId }) {
                            Label(advice.reason, systemImage: "sparkles")
                        }
                        ForEach(Array(plan.recentSessions.enumerated()), id: \.offset) { _, session in
                            LabeledContent {
                                Text(session.sets.map { unit.formatSet(WorkoutSet(reps: $0.reps, weightKg: $0.weightKg)) }.joined(separator: ", "))
                                    .multilineTextAlignment(.trailing)
                            } label: {
                                Text(HealthDays.date(session.date).map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? session.date)
                            }
                        }
                    }
                }
            }
            Section {
            } footer: {
                Text("Your experience, goal and units were sent too. Your name and email address never are.")
            }
        }
        .brandBackground()
        .navigationTitle("What the AI coach used")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: LocalizedStringKey, value: String, usual: String?) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                if let usual {
                    Text("Usual \(usual)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The AI coach switch in Settings (docs/consent-copy.md, section 4), and the
/// IronSage Coach subscription.
struct CoachSettingsSection: View {
    @Environment(CoachService.self) private var coach
    @Environment(SubscriptionService.self) private var subscriptions
    @State private var isAsking = false
    @State private var isConfirmingOff = false
    @State private var showsPaywall = false
    @State private var managesSubscription = false

    var body: some View {
        Section {
            Toggle("AI coach", isOn: Binding(
                get: { coach.isEnabled },
                set: { on in
                    if on {
                        isAsking = true
                    } else {
                        isConfirmingOff = true
                    }
                }
            ))
            // On the row, not the section: a List doesn't present from a section.
            .sheet(isPresented: $isAsking) { CoachConsentView() }
            .alert("Turn off the AI coach?", isPresented: $isConfirmingOff) {
                Button("Turn off", role: .destructive) { coach.turnOff() }
                Button("Keep on", role: .cancel) {}
            } message: {
                Text("You'll stop getting suggestions, and IronSage stops sending data to Anthropic. Past suggestions stay in your history.")
            }
            if let entitlement = subscriptions.entitlement {
                LabeledContent("IronSage Coach") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(entitlement.productID == SubscriptionService.yearly ? LocalizedStringKey("Yearly") : "Monthly")
                        if let expiresAt = entitlement.expiresAt {
                            Group {
                                if entitlement.isTrial && entitlement.willRenew {
                                    Text("Free trial until \(expiresAt, format: .dateTime.month().day())")
                                } else if entitlement.willRenew {
                                    Text("Renews \(expiresAt, format: .dateTime.month().day())")
                                } else {
                                    Text("Ends \(expiresAt, format: .dateTime.month().day())")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Manage subscription") { managesSubscription = true }
                    .manageSubscriptionsSheet(isPresented: $managesSubscription)
            } else if !subscriptions.serverAccess {
                Button("Subscribe to IronSage Coach") { showsPaywall = true }
                    .sheet(isPresented: $showsPaywall) { PaywallSheet() }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(coach.isEnabled
                    ? "Sends your recent training and daily health summaries to Anthropic to prepare suggestions."
                    : "Nothing is sent to Anthropic.")
                if subscriptions.isLinkedElsewhere {
                    Text("This Apple Account's subscription is linked to another IronSage account.")
                } else if coach.isUnavailable && !subscriptions.hasAccess {
                    Text("The AI coach needs an IronSage Coach subscription. Suggested weights and reps stay free.")
                }
            }
        }
    }
}
