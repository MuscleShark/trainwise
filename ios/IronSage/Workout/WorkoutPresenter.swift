import IronSageCore
import IronSageStore
import SwiftUI

/// Shows the workout being logged, over the tabs. Today, a template and the bar above
/// the tabs all open it here, and the session is kept while the screen is hidden, so
/// the rest timer keeps counting and shows in the bar.
@MainActor
@Observable
final class WorkoutPresenter {
    private(set) var session: WorkoutSession?
    var isShowing = false

    func show(_ session: WorkoutSession) {
        self.session = session
        isShowing = true
    }

    /// Opens the workout in progress, with its rest timer when it has one running.
    func resume(_ workout: Workout, store: LocalStore) {
        if session?.id != workout.id {
            session = WorkoutSession(workout: workout, store: store)
        }
        isShowing = true
    }

    /// After the screen closes: a finished or discarded workout's session goes.
    func closed(activeWorkoutID: UUID?) {
        if session?.id != activeWorkoutID {
            session = nil
        }
    }

    /// The bar above the tabs (`tabViewBottomAccessory`), from iOS 26.1, the first that
    /// can hide it when no workout is in progress. Before that, Today shows the workout
    /// in a section of its own.
    static var hasWorkoutBar: Bool {
        if #available(iOS 26.1, *) { true } else { false }
    }
}

extension View {
    /// The workout screen over the tabs, and the bar above them while one is in progress.
    func workoutPresentation(_ presenter: WorkoutPresenter, store: LocalStore) -> some View {
        modifier(WorkoutPresentation(presenter: presenter, store: store))
    }
}

private struct WorkoutPresentation: ViewModifier {
    @Bindable var presenter: WorkoutPresenter
    let store: LocalStore

    func body(content: Content) -> some View {
        bar(content)
            .fullScreenCover(isPresented: $presenter.isShowing) {
                presenter.closed(activeWorkoutID: store.activeWorkout?.id)
            } content: {
                if let session = presenter.session {
                    WorkoutView(session: session)
                }
            }
    }

    @ViewBuilder private func bar(_ content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: store.activeWorkout != nil) {
                if let workout = store.activeWorkout {
                    WorkoutBar(workout: workout, session: presenter.session?.id == workout.id ? presenter.session : nil) {
                        presenter.resume(workout, store: store)
                    }
                }
            }
        } else {
            content
        }
    }
}

/// The workout in progress above the tabs: its name, sets done and the rest left. A tap
/// opens it again.
@available(iOS 26.1, *)
private struct WorkoutBar: View {
    let workout: Workout
    let session: WorkoutSession?
    let open: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button(action: open) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(workout.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Text(detail(at: context.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if placement != .inline {
                        Text("Resume")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.brandOnAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.accentColor, in: .capsule)
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the workout"))
    }

    /// "Rest 2:40" while resting, else "3 of 13 sets".
    private func detail(at date: Date) -> String {
        if let timer = session?.restTimer, !timer.isFinished(at: date) {
            return String(appLocalized: "Rest \(Duration.clock(timer.remaining(at: date)))")
        }
        let sets = workout.exercises.flatMap(\.sets)
        return String(appLocalized: "\(sets.count(where: \.isCompleted)) of \(sets.count) sets")
    }
}
