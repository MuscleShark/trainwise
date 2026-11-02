import Foundation

// Cardio machines and outdoor cardio, drawn as a loop rather than between two poses: the
// feet go round (pedals, an elliptical's oval) or step on (a treadmill's belt, a stair
// climber's turning stairs). Each drawing takes the phase of the loop, 0 to 1. Same box
// and styles as the other figures (see ExerciseVisuals.swift).
//
// Angles here are in degrees from straight down (limbs) or straight up (the torso),
// positive leaning the way the figure faces.

/// A movement drawn from the phase of a loop that repeats every `period` seconds.
struct CyclePattern: Sendable {
    var period: Double
    var draw: @Sendable (Double) -> Figure
}

extension ExerciseVisuals {
    static let cardioPatterns: [String: Pattern] = {
        func cycle(_ period: Double, _ draw: @escaping @Sendable (Double) -> Figure) -> Pattern {
            Pattern(family: .cardio, view: .cycle(CyclePattern(period: period, draw: draw)))
        }
        return [
            "incline_walk": cycle(1.3) { CardioFigure.treadmill($0, .inclineWalk) },
            "treadmill_run": cycle(0.8) { CardioFigure.treadmill($0, .treadmillRun) },
            "walk": cycle(1.2) { CardioFigure.treadmill($0, .walk) },
            "run": cycle(0.8) { CardioFigure.treadmill($0, .run) },
            "stairs": cycle(1.4, CardioFigure.stairs),
            "bike": cycle(1.0, CardioFigure.bike),
            "rower": cycle(2.6, CardioFigure.rower),
            "elliptical": cycle(1.3, CardioFigure.elliptical),
        ]
    }()
}

enum CardioFigure {
    private static let torso = 44.0, neck = 11.0, thigh = 36.0, shin = 34.0, footLength = 11.0, upperArm = 25.0, forearm = 23.0

    // MARK: Geometry

    private static func down(_ degrees: Double) -> Point { Point(sin(degrees * .pi / 180), cos(degrees * .pi / 180)) }
    private static func up(_ degrees: Double) -> Point { Point(sin(degrees * .pi / 180), -cos(degrees * .pi / 180)) }
    private static func along(_ p: Point, _ d: Point, _ length: Double) -> Point { Point(p.x + d.x * length, p.y + d.y * length) }
    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func mix(_ a: Point, _ b: Point, _ t: Double) -> Point { Point(mix(a.x, b.x, t), mix(a.y, b.y, t)) }
    private static func clamp01(_ t: Double) -> Double { min(1, max(0, t)) }
    /// Slow at both ends, quick in between.
    private static func ease(_ t: Double) -> Double { (1 - cos(.pi * t)) / 2 }
    private static func footTip(_ ankle: Point, _ degrees: Double) -> Point {
        along(ankle, Point(cos(degrees * .pi / 180), sin(degrees * .pi / 180)), footLength)
    }

    private enum Bend { case front, back, up, down }

    /// The middle joint of a two-part limb from `a` reaching for `target`, bent to one
    /// side; a target out of reach is pulled in along the line.
    private static func reach(_ a: Point, _ target: Point, _ l1: Double, _ l2: Double, _ bend: Bend) -> (mid: Point, end: Point) {
        var t = target
        var d = hypot(t.x - a.x, t.y - a.y)
        let longest = l1 + l2 - 0.01
        if d > longest {
            t = Point(a.x + (t.x - a.x) / d * longest, a.y + (t.y - a.y) / d * longest)
            d = longest
        }
        d = max(d, abs(l1 - l2) + 0.01)
        let base = atan2(t.y - a.y, t.x - a.x)
        let c = acos(max(-1, min(1, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))))
        let m1 = Point(a.x + l1 * cos(base + c), a.y + l1 * sin(base + c))
        let m2 = Point(a.x + l1 * cos(base - c), a.y + l1 * sin(base - c))
        let mid: Point = switch bend {
        case .front: m1.x >= m2.x ? m1 : m2
        case .back: m1.x < m2.x ? m1 : m2
        case .up: m1.y < m2.y ? m1 : m2
        case .down: m1.y >= m2.y ? m1 : m2
        }
        return (mid, t)
    }

    /// Pieces of a polyline inside a box.
    private static func clipped(_ points: [Point], x0: Double, y0: Double, x1: Double, y1: Double) -> [[Point]] {
        var pieces: [[Point]] = []
        for (a, b) in zip(points, points.dropFirst()) {
            var t0 = 0.0, t1 = 1.0, inside = true
            let dx = b.x - a.x, dy = b.y - a.y
            for (p, q) in [(-dx, a.x - x0), (dx, x1 - a.x), (-dy, a.y - y0), (dy, y1 - a.y)] where inside {
                if p == 0 {
                    if q < 0 { inside = false }
                    continue
                }
                let r = q / p
                if p < 0 {
                    if r > t1 { inside = false } else if r > t0 { t0 = r }
                } else {
                    if r < t0 { inside = false } else if r < t1 { t1 = r }
                }
            }
            if inside { pieces.append([Point(a.x + dx * t0, a.y + dy * t0), Point(a.x + dx * t1, a.y + dy * t1)]) }
        }
        return pieces
    }

    // MARK: The figure

    private static func leg(_ fig: inout Figure, hip: Point, ankle: Point, toe: Point, far: Bool, bend: Bend = .front) {
        let knee = reach(hip, ankle, thigh, shin, bend)
        fig.items.append(.polyline([hip, knee.mid, knee.end, toe], far ? .ghost : .body))
    }

    private static func arm(_ fig: inout Figure, shoulder: Point, hand: Point, far: Bool, bend: Bend = .down) {
        let elbow = reach(shoulder, hand, upperArm, forearm, bend)
        fig.items.append(.polyline([shoulder, elbow.mid, elbow.end], far ? .ghost : .limb))
    }

    private static func swingingArm(_ fig: inout Figure, shoulder: Point, upper: Double, fore: Double, far: Bool) {
        let elbow = along(shoulder, down(upper), upperArm)
        fig.items.append(.polyline([shoulder, elbow, along(elbow, down(fore), forearm)], far ? .ghost : .limb))
    }

    /// The torso and head; returns the shoulder.
    private static func torso(_ fig: inout Figure, hip: Point, lean: Double) -> Point {
        let shoulder = along(hip, up(lean), torso)
        fig.items.append(.polyline([hip, shoulder], .body))
        fig.circle(along(shoulder, up(lean), neck), 7.5, .head)
        return shoulder
    }

    private static func floor(_ fig: inout Figure) {
        fig.line(Point(6, Figure.ground), Point(154, Figure.ground), .ground)
    }

    // MARK: Treadmill, and walking or running outside

    struct Gait: Sendable {
        var slope = 0.0, stride = 20.0, lift = 9.0, stance = 0.6, hipHeight = 62.0, bob = 1.5, lean = 10.0, arm = 20.0, elbow = 18.0
        var outdoor = false

        static let inclineWalk = Gait(slope: 10)
        static let treadmillRun = Gait(stride: 24, lift: 18, stance: 0.38, hipHeight: 60, bob: 2.5, arm: 32, elbow: 80)
        static let walk = Gait(stride: 20, lift: 8, hipHeight: 63, lean: 3, elbow: 15, outdoor: true)
        static let run = Gait(stride: 24, lift: 18, stance: 0.38, hipHeight: 60, bob: 2.5, arm: 32, elbow: 80, outdoor: true)
    }

    static func treadmill(_ phase: Double, _ gait: Gait) -> Figure {
        var fig = Figure()
        let slope = tan(gait.slope * .pi / 180)
        let level = gait.outdoor ? Figure.ground : 128
        func deckY(_ x: Double) -> Double { level - (x - 76) * slope }
        floor(&fig)
        if !gait.outdoor {
            let rear = Point(20, deckY(20)), front = Point(132, deckY(132))
            fig.line(Point(front.x - 4, front.y), Point(140, 60), .scene)
            fig.rect(128, 52, 20, 10, .sceneFill, r: 3)
            fig.line(Point(rear.x + 8, rear.y + 7), Point(rear.x + 8, Figure.ground), .sceneThin)
            fig.line(Point(front.x - 8, front.y + 7), Point(front.x - 8, Figure.ground), .sceneThin)
            fig.items.append(.polyline([rear, front, Point(front.x, front.y + 7), Point(rear.x, rear.y + 7), rear], .sceneFill))
            // Marks on the belt, moving back as fast as a planted foot.
            let speed = 2 * gait.stride / gait.stance, gap = speed / (speed / 14).rounded()
            var x = rear.x + 4 + (gap - (phase * speed).truncatingRemainder(dividingBy: gap))
            while x + 5 < front.x - 2 {
                fig.line(Point(x, deckY(x) + 3.5), Point(x + 5, deckY(x + 5) + 3.5), .sceneThin)
                x += gap
            }
        }

        let hipX = 74.0
        let hip = Point(hipX, deckY(hipX) - 4 - gait.hipHeight + gait.bob * cos(4 * .pi * phase))
        func foot(_ offset: Double) -> (ankle: Point, toe: Point) {
            let u = (phase + offset).truncatingRemainder(dividingBy: 1)
            var x: Double, lift = 0.0, tip = -gait.slope
            if u < gait.stance {
                x = hipX + gait.stride - 2 * gait.stride * (u / gait.stance)
            } else {
                let q = (u - gait.stance) / (1 - gait.stance)
                x = hipX - gait.stride + 2 * gait.stride * ease(q)
                lift = gait.lift * sin(.pi * q)
                tip += 24 * sin(.pi * min(1, q * 1.6))
            }
            let ankle = Point(x, deckY(x) - 4 - lift)
            return (ankle, footTip(ankle, tip))
        }
        let swing = cos(2 * .pi * phase)
        let shoulder = along(hip, up(gait.lean), torso)
        let far = foot(0.5), near = foot(0)
        swingingArm(&fig, shoulder: shoulder, upper: gait.arm * swing, fore: gait.arm * swing + gait.elbow, far: true)
        leg(&fig, hip: hip, ankle: far.ankle, toe: far.toe, far: true)
        _ = torso(&fig, hip: hip, lean: gait.lean)
        leg(&fig, hip: hip, ankle: near.ankle, toe: near.toe, far: false)
        swingingArm(&fig, shoulder: shoulder, upper: -gait.arm * swing, fore: -gait.arm * swing + gait.elbow, far: false)
        return fig
    }

    // MARK: Stair climber

    /// A stepmill: the stairs turn down toward the climber, one step per stride.
    static func stairs(_ phase: Double) -> Figure {
        var fig = Figure()
        floor(&fig)
        fig.rect(30, 140, 90, 6, .sceneFill, r: 3)
        fig.line(Point(114, 141), Point(116, 44), .scene)
        fig.rect(106, 34, 22, 12, .sceneFill, r: 3)
        fig.rect(52, 70, 58, 70, .sceneFill, r: 4)
        let shift = (2 * phase).truncatingRemainder(dividingBy: 1)
        var steps: [Point] = []
        for k in -4...4 {
            let x = 78 + 22 * (Double(k) - shift), y = 121 - 18 * (Double(k) - shift)
            steps += [Point(x, y), Point(x + 22, y), Point(x + 22, y - 18)]
        }
        for piece in clipped(steps, x0: 56, y0: 74, x1: 106, y1: 138) {
            fig.items.append(.polyline(piece, .scene))
        }

        let high = Point(86, 116), low = Point(64, 134)
        func foot(_ offset: Double) -> (ankle: Point, toe: Point) {
            let u = (phase + offset).truncatingRemainder(dividingBy: 1)
            var ankle: Point
            if u < 0.5 {
                ankle = mix(high, low, u / 0.5)
            } else {
                let q = (u - 0.5) / 0.5
                ankle = mix(low, high, ease(q))
                ankle.y -= 14 * sin(.pi * q)
            }
            return (ankle, along(ankle, Point(0.97, 0.24), footLength))
        }
        let hip = Point(70, 66 + 1.5 * cos(4 * .pi * phase)), lean = 14.0
        let shoulder = along(hip, up(lean), torso)
        let far = foot(0.5), near = foot(0)
        arm(&fig, shoulder: shoulder, hand: Point(97, 66), far: true, bend: .back)
        leg(&fig, hip: hip, ankle: far.ankle, toe: far.toe, far: true)
        fig.line(Point(84, 66), Point(114, 63), .scene)
        _ = torso(&fig, hip: hip, lean: lean)
        leg(&fig, hip: hip, ankle: near.ankle, toe: near.toe, far: false)
        arm(&fig, shoulder: shoulder, hand: Point(100, 64), far: false, bend: .back)
        return fig
    }

    // MARK: Exercise bike

    /// A spin bike: the pedals go round, the hips stay on the saddle.
    static func bike(_ phase: Double) -> Figure {
        var fig = Figure()
        let crank = Point(86, 124), radius = 15.0, angle = 2 * .pi * phase
        floor(&fig)
        fig.rect(40, 141, 104, 5, .sceneFill, r: 2.5)
        fig.circle(Point(120, 116), 17, .sceneFill)
        fig.line(crank, Point(86, 141), .sceneThin)
        func pedal(_ a: Double) -> Point { Point(crank.x + radius * sin(a), crank.y - radius * cos(a)) }
        func foot(_ p: Point) -> (ankle: Point, toe: Point) {
            let ankle = Point(p.x - 3, p.y - 4)
            return (ankle, footTip(ankle, 15))
        }
        let nearPedal = pedal(angle), farPedal = pedal(angle + .pi)
        let hip = Point(59, 75), lean = 42.0
        let shoulder = along(hip, up(lean), torso)
        let far = foot(farPedal), near = foot(nearPedal)
        fig.line(crank, farPedal, .sceneThin)
        arm(&fig, shoulder: shoulder, hand: Point(110, 64), far: true)
        leg(&fig, hip: hip, ankle: far.ankle, toe: far.toe, far: true)
        fig.items.append(.polyline([Point(58, 84), crank, Point(114, 70)], .scene))
        fig.line(Point(48, 80), Point(66, 80), .scene)
        fig.items.append(.polyline([Point(114, 70), Point(118, 62), Point(106, 62)], .scene))
        _ = torso(&fig, hip: hip, lean: lean)
        leg(&fig, hip: hip, ankle: near.ankle, toe: near.toe, far: false)
        fig.line(crank, nearPedal, .lever)
        fig.circle(crank, 3, .accent)
        arm(&fig, shoulder: shoulder, hand: Point(112, 63), far: false)
        return fig
    }

    // MARK: Rowing machine

    /// Legs, then body, then arms on the drive; back in the opposite order.
    static func rower(_ phase: Double) -> Figure {
        var fig = Figure()
        let p = phase < 0.4 ? ease(phase / 0.4) : 1 - ease((phase - 0.4) / 0.6)
        let legs = clamp01(p / 0.55), body = clamp01((p - 0.35) / 0.4), arms = clamp01((p - 0.6) / 0.4)
        let chain = Point(128, 112)
        floor(&fig)
        fig.rect(14, 137, 122, 5, .sceneFill, r: 2.5)
        fig.line(Point(24, 142), Point(24, Figure.ground), .sceneThin)
        fig.circle(Point(138, 120), 15, .sceneFill)
        fig.line(Point(110, 138), Point(121, 108), .scene)

        let hip = Point(mix(76, 46, ease(legs)), 125), lean = mix(30, -24, ease(body))
        fig.rect(hip.x - 10, 128, 20, 6, .sceneFill, r: 2.5)
        let shoulder = along(hip, up(lean), torso)
        let toward = Point(chain.x - shoulder.x, chain.y - shoulder.y), length = hypot(toward.x, toward.y)
        let straight = along(shoulder, Point(toward.x / length, toward.y / length), min(length, 47))
        let r = lean * .pi / 180
        let chest = Point(shoulder.x - 16 * sin(r) + 10 * cos(r), shoulder.y + 16 * cos(r) + 10 * sin(r))
        let hand = mix(straight, chest, ease(arms))
        let ankle = Point(113, 128), toe = along(ankle, Point(0.36, -0.93), footLength)
        func nudged(_ p: Point) -> Point { Point(p.x + 2, p.y - 1) }

        leg(&fig, hip: nudged(hip), ankle: nudged(ankle), toe: nudged(toe), far: true, bend: .up)
        arm(&fig, shoulder: nudged(shoulder), hand: nudged(hand), far: true, bend: .back)
        _ = torso(&fig, hip: hip, lean: lean)
        leg(&fig, hip: hip, ankle: ankle, toe: toe, far: false, bend: .up)
        fig.line(hand, chain, .cable)
        arm(&fig, shoulder: shoulder, hand: hand, far: false, bend: .back)
        fig.line(Point(hand.x, hand.y - 5), Point(hand.x, hand.y + 5), .lever)
        return fig
    }

    // MARK: Elliptical

    /// The pedals trace an oval; the handles swing against the feet.
    static func elliptical(_ phase: Double) -> Figure {
        var fig = Figure()
        let angle = 2 * .pi * phase, center = Point(80, 124), pivot = Point(116, 124), flywheel = Point(30, 120)
        floor(&fig)
        fig.rect(22, 140, 102, 6, .sceneFill, r: 3)
        fig.circle(flywheel, 16, .sceneFill)
        fig.line(Point(116, 141), Point(120, 50), .scene)
        fig.rect(112, 38, 22, 12, .sceneFill, r: 3)
        func pedal(_ a: Double) -> Point {
            let x = 20 * cos(a), y = 7 * sin(a), tilt = -10 * Double.pi / 180
            return Point(center.x + x * cos(tilt) - y * sin(tilt), center.y + x * sin(tilt) + y * cos(tilt))
        }
        func grip(_ a: Double) -> Point { along(pivot, up(-20 - 12 * cos(a)), 80) }
        func foot(_ p: Point) -> (ankle: Point, toe: Point) {
            let ankle = Point(p.x - 3, p.y - 5)
            return (ankle, footTip(ankle, 8))
        }
        let nearPedal = pedal(angle), farPedal = pedal(angle + .pi)
        let hip = Point(70, 66 + 1.5 * cos(4 * .pi * phase)), lean = 6.0
        let shoulder = along(hip, up(lean), torso)
        let far = foot(farPedal), near = foot(nearPedal), farGrip = grip(angle + .pi), nearGrip = grip(angle)
        fig.line(flywheel, farPedal, .sceneThin)
        fig.line(pivot, farGrip, .sceneThin)
        arm(&fig, shoulder: shoulder, hand: farGrip, far: true)
        leg(&fig, hip: hip, ankle: far.ankle, toe: far.toe, far: true)
        _ = torso(&fig, hip: hip, lean: lean)
        leg(&fig, hip: hip, ankle: near.ankle, toe: near.toe, far: false)
        fig.line(flywheel, nearPedal, .lever)
        fig.line(Point(nearPedal.x - 9, nearPedal.y + 1), Point(nearPedal.x + 9, nearPedal.y + 1), .scene)
        fig.line(pivot, nearGrip, .lever)
        arm(&fig, shoulder: shoulder, hand: nearGrip, far: false)
        return fig
    }
}
