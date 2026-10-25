import IronSageCore
import IronSageStore
import SwiftUI

/// Shown when a workout is finished: how long, how much, and any new records.
struct WorkoutSummaryView: View {
    let workout: Workout
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let unit = store.weightUnit
        let records = WorkoutLog.personalRecords(in: workout, history: store.finishedWorkouts, exercises: store.exercises)
        NavigationStack {
            List {
                Section {
                    LabeledContent("Duration", value: Duration.clock((workout.endedAt ?? .now).timeIntervalSince(workout.startedAt)))
                    LabeledContent("Exercises", value: workout.exercises.count.formatted())
                    LabeledContent("Sets", value: workout.exercises.map(\.sets.count).reduce(0, +).formatted())
                    LabeledContent("Volume", value: unit.formatTotal(kilograms: WorkoutLog.volumeKg(of: workout, exercises: store.exercises)))
                } footer: {
                    Text("Volume is weight × reps of the working sets; one dumbbell per side counts twice.")
                }

                if !records.isEmpty {
                    Section("New records") {
                        ForEach(records, id: \.self) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.exerciseName(record.exerciseID))
                                Group {
                                    switch record.kind {
                                    case .heaviestWeight:
                                        Text("Heaviest set: \(unit.formatWithUnit(kilograms: record.kilograms)), up from \(unit.formatWithUnit(kilograms: record.previousKilograms))")
                                    case .estimatedOneRepMax:
                                        Text("Estimated 1RM: \(unit.formatWithUnit(kilograms: record.kilograms)), up from \(unit.formatWithUnit(kilograms: record.previousKilograms))")
                                    }
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(workout.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
