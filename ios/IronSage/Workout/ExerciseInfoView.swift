import IronSageCore
import IronSageStore
import SwiftUI

/// How to do an exercise: the moving figure, the muscles it works and a few form cues.
/// Opened from ⓘ in the exercise list and on the workout screen.
struct ExerciseInfoView: View {
    let exercise: Exercise
    /// Shown as an Add button when the sheet was opened from the exercise list.
    var onAdd: (() -> Void)?
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var movement: Movement? { ExerciseVisuals.movement(for: exercise) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stage
                    if let base = exercise.baseExerciseId.flatMap({ store.exercises[$0] }), movement != nil {
                        Text("Shown as \(base.name(chinese: AppLanguage.isChinese)), the exercise this is a variation of.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    section("Muscles") {
                        MuscleMapView(primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles)
                        FlowLayout(spacing: 6) {
                            ForEach(exercise.primaryMuscles, id: \.self) { chip($0, primary: true) }
                            ForEach(exercise.secondaryMuscles, id: \.self) { chip($0, primary: false) }
                        }
                    }
                    if let movement {
                        section("How to do it") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(movement.family.cues.enumerated()), id: \.offset) { index, cue in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(index + 1, format: .number)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.tint)
                                        Text(cue)
                                    }
                                }
                            }
                        }
                    }
                    Text("Training guidance, not medical advice. Stop if something hurts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle(exercise.name(chinese: AppLanguage.isChinese))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if let onAdd {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            onAdd()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        if let movement {
            AnimatedFigureView(movement: movement, equipment: exercise.equipment, isPlaying: !reduceMotion, background: Self.card)
                .aspectRatio(1.2, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Self.card, in: .rect(cornerRadius: 16))
                .overlay(alignment: .topLeading) {
                    if movement.isHold {
                        Text("Hold")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.tint.opacity(0.15), in: .capsule)
                            .padding(12)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(movement.family.title))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "dumbbell")
                    .font(.largeTitle)
                Text("No picture for this exercise yet.")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(Self.card, in: .rect(cornerRadius: 16))
        }
    }

    /// "Barbell · Total weight · Squat"
    private var summary: String {
        var parts = [String(localized: exercise.equipment.label), String(localized: exercise.loadType.label)]
        if let movement { parts.append(String(localized: movement.family.title)) }
        return parts.joined(separator: " · ")
    }

    private func section(_ title: LocalizedStringResource, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Self.card, in: .rect(cornerRadius: 12))
        }
    }

    private func chip(_ muscle: Muscle, primary: Bool) -> some View {
        Text(muscle.label)
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(primary ? Color.white : Color.primary)
            .background(primary ? Color.accentColor : Color.accentColor.opacity(0.15), in: .capsule)
            .accessibilityLabel(primary ? Text("Main: \(String(localized: muscle.label))") : Text("Also works: \(String(localized: muscle.label))"))
    }

    private static let card = Color(.secondarySystemGroupedBackground)
}

/// Rows of chips that wrap to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

extension MovementFamily {
    var title: LocalizedStringResource {
        switch self {
        case .squat: "Squat"
        case .lunge: "Lunge"
        case .legPress: "Leg press"
        case .hinge: "Hip hinge"
        case .power: "Power"
        case .row: "Row"
        case .verticalPull: "Pull-down"
        case .press: "Press"
        case .overheadPress: "Overhead press"
        case .fly: "Fly"
        case .raise: "Raise"
        case .curl: "Curl"
        case .triceps: "Triceps extension"
        case .dip: "Dip"
        case .pushUp: "Push-up"
        case .kneeMachine: "Knee machine"
        case .glute: "Glutes"
        case .calf: "Calf raise"
        case .core: "Core"
        case .hold: "Hold"
        case .carry: "Carry"
        case .shrug: "Shrug"
        case .hipMachine: "Hip machine"
        case .backExtension: "Back extension"
        }
    }

    /// Three form cues for every exercise that moves this way.
    var cues: [LocalizedStringResource] {
        switch self {
        case .squat: ["Brace your core and keep your whole foot on the floor.", "Sit down between your hips until your thighs reach parallel or lower.", "Keep your knees over your toes and drive up through mid-foot."]
        case .lunge: ["Take a long enough step that your front heel stays down.", "Lower your back knee straight down toward the floor.", "Push through your front foot to stand back up."]
        case .legPress: ["Keep your lower back flat against the pad.", "Lower until your knees are bent about 90°.", "Press through your whole foot without snapping your knees straight."]
        case .hinge: ["Keep the weight close to your legs the whole way.", "Push your hips back and keep your back flat.", "Stand up by driving your hips forward; don't lean back at the top."]
        case .power: ["Start with a flat back and the weight close.", "Drive with your hips and legs; your arms only guide the weight.", "Finish with soft knees and a tall chest."]
        case .row: ["Set your torso and keep your back flat.", "Pull your elbows back toward your hips.", "Squeeze your shoulder blades, then lower under control."]
        case .verticalPull: ["Start from a full stretch with straight arms.", "Pull your elbows down to your sides with your chest up.", "Let the weight back up slowly."]
        case .press: ["Pull your shoulder blades back and keep them there.", "Lower to mid-chest with your elbows about 45° from your body.", "Press up until your arms are straight, under control."]
        case .overheadPress: ["Squeeze your glutes and brace your core.", "Press straight up; move your head through at the top.", "Lower to chin height under control."]
        case .fly: ["Keep a small, fixed bend in your elbows.", "Open wide until you feel a stretch across your chest.", "Bring your hands together in an arc, like a hug."]
        case .raise: ["Keep a small bend in your elbows.", "Raise to shoulder height, no higher.", "Lower slowly without swinging."]
        case .curl: ["Keep your elbows still at your sides.", "Curl up without swinging your body.", "Lower all the way under control."]
        case .triceps: ["Keep your upper arms still.", "Straighten your elbows fully.", "Return slowly to a full stretch."]
        case .dip: ["Keep your shoulders down, away from your ears.", "Lower until your upper arms are about parallel to the floor.", "Press back up to straight arms."]
        case .pushUp: ["Make a straight line from head to heels.", "Lower your chest to just above the floor.", "Push the floor away to straight arms."]
        case .kneeMachine: ["Line your knee up with the machine's pivot.", "Move through the full range.", "Pause at the hardest point, then lower slowly."]
        case .glute: ["Tuck your chin and keep your ribs down.", "Drive through your heels until your hips are level.", "Squeeze your glutes at the top without arching your back."]
        case .calf: ["Start from a full stretch at the bottom.", "Rise as high as you can onto your toes.", "Pause at the top, then lower slowly."]
        case .core: ["Keep your lower back neutral or pressed down.", "Breathe out as you curl or lift.", "Move slowly and stop before your back arches."]
        case .hold: ["Pull your ribs down and squeeze your glutes.", "Keep a straight line through your body.", "Breathe steadily; stop when your form breaks."]
        case .carry: ["Stand tall with your shoulders back.", "Take short, quick steps.", "Grip hard and don't let the weight swing."]
        case .shrug: ["Hold the weight at your sides with straight arms.", "Lift your shoulders straight up toward your ears.", "Pause, then lower all the way."]
        case .hipMachine: ["Sit tall against the back pad.", "Move your knees out or in through the full range.", "Control the return; don't let the stack slam."]
        case .backExtension: ["Set your hips at the edge of the pad.", "Lower with a flat back.", "Rise until your body is straight, not past it."]
        }
    }
}
