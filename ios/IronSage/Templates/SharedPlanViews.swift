import IronSageCore
import IronSageStore
import os
import SwiftUI

private let log = Logger(subsystem: "app.ironsage.IronSage", category: "sharing")

/// A shared link the app was opened with, waiting to be shown over the tabs.
@MainActor
@Observable
final class SharedPlanOpener {
    static let shared = SharedPlanOpener()

    struct Opened: Identifiable {
        let code: String
        var id: String { code }
    }

    var opened: Opened?

    func open(code: String) {
        opened = Opened(code: code)
    }
}

/// A plan someone shared: what it holds, and Copy to my templates. Opened from its link
/// (ironsage.app/p/<code>) or from a link pasted in Templates.
struct SharedPlanView: View {
    let code: String
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(\.api) private var api
    @Environment(\.dismiss) private var dismiss
    @Environment(\.selectTab) private var selectTab
    @State private var state = LoadState.loading
    @State private var isCopying = false
    @State private var copyFailure: SharingError?

    private enum LoadState {
        case loading
        case loaded(SharedPlan)
        case failed(SharingError)
    }

    private var chinese: Bool { AppLanguage.isChinese }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                ContentUnavailableView {
                    Label(error == .notFound ? "This plan isn't shared anymore" : "Couldn't open the plan", systemImage: "link")
                } description: {
                    Text(error == .notFound ? "The link was stopped, or the plan was deleted." : "Check your connection and try again.")
                } actions: {
                    if error != .notFound {
                        Button("Try again") { Task { await load() } }
                    }
                }
            case .loaded(let plan):
                planList(plan)
            }
        }
        .brandBackground()
        .navigationTitle("Shared plan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert(
            "Couldn't copy the plan",
            isPresented: Binding(get: { copyFailure != nil }, set: { if !$0 { copyFailure = nil } }),
            presenting: copyFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            switch failure {
            case .signedOut: Text("Sign in to copy plans into your templates.")
            case .notFound: Text("This plan isn't shared anymore.")
            default: Text("Check your connection and try again.")
            }
        }
    }

    private func planList(_ plan: SharedPlan) -> some View {
        let template = plan.template
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.name(chinese: chinese))
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 4) {
                        Text("^[\(template.days.count) day](inflect: true)")
                        if let days = template.daysPerWeek {
                            Text(verbatim: "·")
                            Text("\(days) days a week")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let notes = template.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .padding(.top, 4)
                    }
                }
                // Clear, in line with the cards' edges; a zero inset clips the first letter.
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
            }

            ForEach(template.days) { day in
                Section(day.name(chinese: chinese)) {
                    ForEach(day.exercises) { item in
                        let target = TemplateTarget(item: item, exercise: store.exercises[item.exerciseId], unit: store.weightUnit)
                        AdaptiveRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.exercises[item.exerciseId]?.name(chinese: chinese) ?? store.exerciseName(item.exerciseId))
                                if let rest = target.rest {
                                    Text(rest)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } trailing: {
                            Text(target.summary)
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {
                    Task { await copy(plan) }
                } label: {
                    if isCopying {
                        ProgressView().tint(Color.brandOnAccent)
                    } else {
                        Label("Copy to my templates", systemImage: "plus")
                    }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(isCopying)
                .accessibilityIdentifier("copySharedPlan")
                Text("The copy is yours to change. The person who shared it won't see your changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func load() async {
        state = .loading
        guard let api else {
            state = .failed(.offline)
            return
        }
        do {
            state = .loaded(try await TemplateSharing(api: api).plan(code: code))
        } catch let error as SharingError {
            state = .failed(error)
        } catch {
            log.error("Opening a shared plan failed: \(String(describing: error), privacy: .public)")
            state = .failed(.server(status: 0))
        }
    }

    private func copy(_ plan: SharedPlan) async {
        guard let api else { return }
        isCopying = true
        defer { isCopying = false }
        do {
            _ = try await TemplateSharing(api: api).copy(code: plan.code)
            // The server added it; the sync brings it (and any custom exercise) here.
            await sync.sync()
            selectTab(.templates)
            dismiss()
        } catch let error as SharingError {
            copyFailure = error
        } catch {
            log.error("Copying a shared plan failed: \(String(describing: error), privacy: .public)")
            copyFailure = .server(status: 0)
        }
    }
}

/// Templates › Add a shared plan: paste a link someone sent, or its code.
struct AddSharedPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var opened: String?

    private var code: String? { SharedPlanLink.code(in: text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link or code", text: $text, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(open)
                        .accessibilityIdentifier("sharedPlanLink")
                    PasteButton(payloadType: String.self) { strings in
                        guard let pasted = strings.first else { return }
                        text = pasted
                        open()
                    }
                    .labelStyle(.titleAndIcon)
                } footer: {
                    if !text.isEmpty && code == nil {
                        Text("That isn't a link to a shared plan. It looks like https://ironsage.app/p/…")
                    } else {
                        Text("Paste a link someone shared with you, such as https://ironsage.app/p/k3T9xQ2mLa.")
                    }
                }
            }
            .brandBackground()
            .navigationTitle("Add a shared plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open", action: open)
                        .disabled(code == nil)
                }
            }
            .navigationDestination(item: $opened) { code in
                SharedPlanView(code: code)
            }
        }
    }

    private func open() {
        guard let code else { return }
        opened = code
    }
}

/// A template's Share page: its link, to send or copy, and Stop sharing. Opening it
/// shares the template as it is now, so what was sent before is updated too.
struct ShareTemplateView: View {
    let template: Template
    @Environment(SyncEngine.self) private var sync
    @Environment(\.api) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var failure: SharingError?
    @State private var isStopping = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                if let code {
                    let url = SharedPlanLink.url(code: code)
                    Section {
                        Text(url.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("sharedPlanURL")
                        ShareLink(item: url, subject: Text(template.nameEn), message: Text(template.nameEn)) {
                            Label("Share link", systemImage: "square.and.arrow.up")
                        }
                        Button(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc") {
                            UIPasteboard.general.url = url
                            copied = true
                        }
                    } footer: {
                        Text("Anyone with the link can see this plan and copy it into IronSage. It doesn't show your name. Changes you make later are only shared when you open Share again.")
                    }
                    Section {
                        Button("Stop sharing", role: .destructive) {
                            Task { await stop() }
                        }
                        .disabled(isStopping)
                    } footer: {
                        Text("The link stops working. Copies people already made stay theirs.")
                    }
                } else if let failure {
                    ContentUnavailableView {
                        Label("Couldn't share the plan", systemImage: "link")
                    } description: {
                        Text(failure == .signedOut ? "Sign in to share plans." : "Check your connection and try again.")
                    } actions: {
                        Button("Try again") { Task { await share() } }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .brandBackground()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await share() }
        }
    }

    private func share() async {
        failure = nil
        guard let api else {
            failure = .offline
            return
        }
        // The server shares what it has: send this phone's latest edits first.
        await sync.sync()
        do {
            code = try await TemplateSharing(api: api).share(template.id)
        } catch let error as SharingError {
            failure = error
        } catch {
            log.error("Sharing a template failed: \(String(describing: error), privacy: .public)")
            failure = .server(status: 0)
        }
    }

    private func stop() async {
        guard let api else { return }
        isStopping = true
        defer { isStopping = false }
        do {
            try await TemplateSharing(api: api).stopSharing(template.id)
            dismiss()
        } catch {
            log.error("Stopping a share failed: \(String(describing: error), privacy: .public)")
            failure = (error as? SharingError) ?? .server(status: 0)
            code = nil
        }
    }
}
