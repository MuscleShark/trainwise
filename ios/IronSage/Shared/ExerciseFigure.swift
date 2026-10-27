import IronSageCore
import SwiftUI

/// A movement's stick figure at one point of the movement (see ExerciseVisuals).
struct FigureView: View {
    let movement: Movement
    let equipment: Equipment
    /// 0 is the start pose, 1 the end pose.
    var progress: Double = 1
    /// What's behind the figure; the inside of a plate is painted with it.
    var background: Color = .appBackground
    /// Enlarged to fill the frame, for thumbnails.
    var zoomed = false

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / Figure.size
            context.translateBy(x: (size.width - Figure.size * scale) / 2, y: (size.height - Figure.size * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            for item in movement.figure(at: progress, equipment: equipment, zoomed: zoomed).items {
                draw(item, in: &context)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ item: Figure.Item, in context: inout GraphicsContext) {
        switch item {
        case .polyline(let points, let style):
            var path = Path()
            path.addLines(points.map { CGPoint(x: $0.x, y: $0.y) })
            stroke(path, style, in: &context)
        case .circle(let center, let radius, let style):
            let path = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            fillOrStroke(path, style, in: &context)
        case .rect(let x, let y, let width, let height, let cornerRadius, let style):
            let path = Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: cornerRadius)
            fillOrStroke(path, style, in: &context)
        }
    }

    private func stroke(_ path: Path, _ style: Figure.Style, in context: inout GraphicsContext) {
        let round = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
        func line(_ width: Double, dash: [CGFloat] = []) -> StrokeStyle {
            var s = round
            s.lineWidth = width
            s.dash = dash
            return s
        }
        switch style {
        case .body: context.stroke(path, with: .color(.brandInk), style: line(6.5))
        case .limb: context.stroke(path, with: .color(.brandInk), style: line(5))
        case .ghost: context.stroke(path, with: .color(.brandInk.opacity(0.35)), style: line(5))
        case .scene: context.stroke(path, with: .color(Self.scene), style: line(4))
        case .sceneThin: context.stroke(path, with: .color(Self.scene), style: line(2.5))
        case .ground: context.stroke(path, with: .color(Self.scene.opacity(0.6)), style: line(1.5))
        case .lever: context.stroke(path, with: .color(.accentColor), style: line(3))
        case .cable: context.stroke(path, with: .color(.accentColor), style: line(1.6, dash: [3, 3]))
        case .head, .plate, .accent, .sceneFill: fillOrStroke(path, style, in: &context)
        }
    }

    private func fillOrStroke(_ path: Path, _ style: Figure.Style, in context: inout GraphicsContext) {
        switch style {
        case .head: context.fill(path, with: .color(.brandInk))
        case .accent: context.fill(path, with: .color(.accentColor))
        case .plate:
            context.fill(path, with: .color(background))
            context.stroke(path, with: .color(.accentColor), lineWidth: 4)
        case .sceneFill:
            context.fill(path, with: .color(Self.scene.opacity(0.35)))
            context.stroke(path, with: .color(Self.scene), lineWidth: 1.5)
        default: stroke(path, style, in: &context)
        }
    }

    private static let scene = Color.secondary.opacity(0.55)
}

/// The figure moving back and forth between its poses, or still when paused.
struct AnimatedFigureView: View {
    let movement: Movement
    let equipment: Equipment
    let isPlaying: Bool
    var background: Color = .appBackground

    /// Where in the loop the figure was at `date`: 0 start, 0.5 end, 1 start again.
    @State private var anchor = (date: Date.now, phase: 0.5)
    private static let period = 2.8

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { context in
            FigureView(movement: movement, equipment: equipment, progress: Self.ease(phase(at: context.date)), background: background)
        }
        .onChange(of: isPlaying) {
            // Pausing keeps the current pose; playing resumes from it.
            anchor = (Date.now, isPlaying ? anchor.phase : phase(at: .now))
        }
    }

    private func phase(at date: Date) -> Double {
        guard isPlaying else { return anchor.phase }
        return (anchor.phase + date.timeIntervalSince(anchor.date) / Self.period).truncatingRemainder(dividingBy: 1)
    }

    /// Slow at both poses, quick in between.
    private static func ease(_ phase: Double) -> Double { (1 - cos(phase * 2 * .pi)) / 2 }
}

/// A small still picture of an exercise for lists, or its equipment when it has none.
struct ExerciseThumbnail: View {
    let exercise: Exercise?
    var size: CGFloat = 40
    var background: Color = .appBackground

    var body: some View {
        Group {
            if let exercise, let movement = ExerciseVisuals.movement(for: exercise) {
                FigureView(movement: movement, equipment: exercise.equipment, background: background, zoomed: true)
                    .padding(3)
            } else {
                Image(systemName: "dumbbell")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(background, in: .rect(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
    }
}

/// Front and back of a body with the muscles an exercise works filled in.
struct MuscleMapView: View {
    let primary: [Muscle]
    let secondary: [Muscle]

    var body: some View {
        HStack(spacing: 12) {
            side(Self.front, label: "Front")
            side(Self.back, label: "Back")
        }
        .accessibilityElement(children: .ignore)
    }

    private func side(_ map: [Muscle: [CGRect]], label: LocalizedStringResource) -> some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let scale = min(size.width / 100, size.height / 210)
                context.translateBy(x: (size.width - 100 * scale) / 2 - 10 * scale, y: -6 * scale)
                context.scaleBy(x: scale, y: scale)
                context.fill(Path(ellipseIn: CGRect(x: 49, y: 11, width: 22, height: 22)), with: .color(Self.idle))
                for (muscle, shapes) in map {
                    let color = primary.contains(muscle) ? Color.accentColor
                        : secondary.contains(muscle) ? Color.accentColor.opacity(0.35) : Self.idle
                    for shape in shapes { context.fill(Path(ellipseIn: shape), with: .color(color)) }
                }
            }
            .aspectRatio(100 / 210, contentMode: .fit)
            .frame(maxHeight: 170)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private static let idle = Color.secondary.opacity(0.18)

    /// Each muscle as ellipses (center x, center y, x radius, y radius) on a 120 × 220 body.
    private static func shapes(_ list: [(Double, Double, Double, Double)]) -> [CGRect] {
        list.map { CGRect(x: $0.0 - $0.2, y: $0.1 - $0.3, width: $0.2 * 2, height: $0.3 * 2) }
    }

    private static let front: [Muscle: [CGRect]] = [
        .chest: shapes([(49, 60, 11, 9), (71, 60, 11, 9)]),
        .frontDelts: shapes([(37, 49, 6, 8), (83, 49, 6, 8)]),
        .sideDelts: shapes([(31, 54, 4.5, 8), (89, 54, 4.5, 8)]),
        .biceps: shapes([(31, 76, 5, 11), (89, 76, 5, 11)]),
        .forearms: shapes([(27, 103, 4.5, 13), (93, 103, 4.5, 13)]),
        .abs: shapes([(60, 92, 8, 19)]),
        .obliques: shapes([(47, 94, 4, 14), (73, 94, 4, 14)]),
        .quads: shapes([(49, 148, 8.5, 22), (71, 148, 8.5, 22)]),
        .adductors: shapes([(56, 136, 3.5, 13), (64, 136, 3.5, 13)]),
        .abductors: shapes([(42, 123, 3.5, 9), (78, 123, 3.5, 9)]),
        .calves: shapes([(49, 192, 5, 14), (71, 192, 5, 14)]),
    ]

    private static let back: [Muscle: [CGRect]] = [
        .traps: shapes([(60, 46, 14, 7)]),
        .rearDelts: shapes([(37, 50, 6, 8), (83, 50, 6, 8)]),
        .sideDelts: shapes([(31, 54, 4.5, 8), (89, 54, 4.5, 8)]),
        .upperBack: shapes([(60, 64, 15, 8)]),
        .lats: shapes([(47, 82, 8, 14), (73, 82, 8, 14)]),
        .triceps: shapes([(31, 76, 5, 11), (89, 76, 5, 11)]),
        .forearms: shapes([(27, 103, 4.5, 13), (93, 103, 4.5, 13)]),
        .lowerBack: shapes([(60, 101, 8, 9)]),
        .glutes: shapes([(51, 124, 9, 9), (69, 124, 9, 9)]),
        .abductors: shapes([(42, 118, 3.5, 7), (78, 118, 3.5, 7)]),
        .hamstrings: shapes([(49, 154, 7.5, 19), (71, 154, 7.5, 19)]),
        .adductors: shapes([(57, 140, 3, 10), (63, 140, 3, 10)]),
        .calves: shapes([(49, 192, 6, 14), (71, 192, 6, 14)]),
    ]
}
