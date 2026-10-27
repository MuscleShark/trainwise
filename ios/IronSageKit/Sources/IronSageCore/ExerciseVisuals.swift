import CryptoKit
import Foundation

// Pictures of how each built-in exercise moves, drawn by the app instead of shipped as
// image files. Each movement is a stick figure in two key poses (start and end) given as
// joint angles; the app draws any point between them, so one pose pair serves every
// exercise that moves the same way and only the equipment changes.
//
// Angles are in degrees: 0 points up, 90 points the way the figure faces (right),
// 180 down. Drawings use a 160 × 160 box with the floor at y = 146.

public enum ExerciseVisuals {
    /// The movement drawn for an exercise: its own, else its base exercise's (for a
    /// custom variation), else none.
    public static func movement(for exercise: Exercise) -> Movement? {
        movement(forID: exercise.id) ?? exercise.baseExerciseId.flatMap(movement(forID:))
    }

    public static func movement(forID id: UUID) -> Movement? {
        byExerciseID[id].flatMap(movement(named:))
    }

    static func movement(named name: String) -> Movement? {
        patterns[name].map { Movement(name: name, pattern: $0) }
    }

    /// The ID the API gives a built-in exercise: a version 5 UUID of its slug (see
    /// backend/catalog.py).
    public static func builtinID(slug: String) -> UUID {
        var data = withUnsafeBytes(of: catalogNamespace.uuid) { Data($0) }
        data.append(Data("exercise:\(slug)".utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static let catalogNamespace = UUID(uuidString: "6f1c2a52-3b7e-4f0a-9a51-1d8e4c7b2f10")!

    private static let byExerciseID: [UUID: String] = Dictionary(
        uniqueKeysWithValues: movementBySlug.map { (builtinID(slug: $0.key), $0.value) }
    )
}

/// One movement: how to draw it and which form cues go with it.
public struct Movement: Sendable, Hashable {
    public let name: String
    let pattern: Pattern

    public var family: MovementFamily { pattern.family }
    /// A static hold (a plank), shown as a hold rather than as reps.
    public var isHold: Bool { pattern.isHold }

    /// The figure `progress` of the way from the start pose (0) to the end pose (1),
    /// fitted so the whole movement stays inside the 160 × 160 box. `zoomed` also
    /// enlarges it to fill the box, for small thumbnails.
    public func figure(at progress: Double, equipment: Equipment, zoomed: Bool = false) -> Figure {
        let u = min(max(progress, 0), 1)
        var bounds = Bounds()
        for sample in [0, 0.25, 0.5, 0.75, 1.0] { bounds.add(raw(at: sample, equipment: equipment)) }
        return raw(at: u, equipment: equipment).fitted(from: bounds, zoomed: zoomed)
    }

    private func raw(at u: Double, equipment: Equipment) -> Figure {
        switch pattern.view {
        case .side(let side): side.figure(at: u, equipment: equipment)
        case .front(let front): front.figure(at: u, equipment: equipment)
        }
    }

    public static func == (lhs: Movement, rhs: Movement) -> Bool { lhs.name == rhs.name }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

/// Movements that share the same form cues.
public enum MovementFamily: String, Sendable, CaseIterable {
    case squat, lunge, legPress, hinge, power, row, verticalPull, press, overheadPress
    case fly, raise, curl, triceps, dip, pushUp, kneeMachine, glute, calf, core, hold
    case carry, shrug, hipMachine, backExtension
}

// MARK: - What gets drawn

public struct Point: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    static func + (a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y) }
}

public struct Figure: Sendable {
    public enum Style: Sendable {
        /// Legs and torso, and the head.
        case body, head
        /// The arm nearest the viewer.
        case limb
        /// The far arm or leg, drawn faint.
        case ghost
        /// Benches, seats, bars and other fixed things.
        case scene, sceneThin, sceneFill, ground
        /// The weight and what it hangs from, in the accent color.
        case plate, accent, lever, cable
    }

    public enum Item: Sendable {
        case polyline([Point], Style)
        case circle(Point, radius: Double, Style)
        case rect(x: Double, y: Double, width: Double, height: Double, cornerRadius: Double, Style)
    }

    public static let size = 160.0
    public static let ground = 146.0

    public var items: [Item] = []

    /// Scaled down and shifted, if needed, so everything within `bounds` fits the box
    /// with a small margin; `zoomed` scales it up to fill the box and centers it. The
    /// floor line keeps its full width.
    func fitted(from bounds: Bounds, zoomed: Bool = false) -> Figure {
        let margin = 4.0, room = Figure.size - 2 * margin
        let fit = min(room / (bounds.maxX - bounds.minX), room / (bounds.maxY - bounds.minY))
        let scale = zoomed ? fit : min(1, fit)
        func shift(_ lo: Double, _ hi: Double) -> Double {
            let lo = lo * scale, hi = hi * scale
            if zoomed { return (Figure.size - lo - hi) / 2 }
            if lo < margin { return margin - lo }
            if hi > Figure.size - margin { return Figure.size - margin - hi }
            return 0
        }
        let dx = shift(bounds.minX, bounds.maxX), dy = shift(bounds.minY, bounds.maxY)
        if scale == 1, dx == 0, dy == 0 { return self }
        func map(_ p: Point) -> Point { Point(p.x * scale + dx, p.y * scale + dy) }
        var out = Figure()
        out.items = items.map { item in
            switch item {
            case .polyline(let points, .ground):
                let y = map(points[0]).y
                return .polyline([Point(6, y), Point(154, y)], .ground)
            case .polyline(let points, let style):
                return .polyline(points.map(map), style)
            case .circle(let center, let radius, let style):
                return .circle(map(center), radius: radius * scale, style)
            case .rect(let x, let y, let w, let h, let r, let style):
                let origin = map(Point(x, y))
                return .rect(x: origin.x, y: origin.y, width: w * scale, height: h * scale, cornerRadius: r * scale, style)
            }
        }
        return out
    }

    mutating func line(_ a: Point, _ b: Point, _ style: Style) { items.append(.polyline([a, b], style)) }
    mutating func circle(_ p: Point, _ r: Double, _ style: Style) { items.append(.circle(p, radius: r, style)) }
    mutating func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ style: Style, r: Double = 2) {
        items.append(.rect(x: x, y: y, width: w, height: h, cornerRadius: r, style))
    }
}

/// The area a figure covers, counting line widths and circle radii but not the floor.
struct Bounds {
    var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity

    mutating func add(_ p: Point, _ pad: Double) {
        minX = min(minX, p.x - pad); maxX = max(maxX, p.x + pad)
        minY = min(minY, p.y - pad); maxY = max(maxY, p.y + pad)
    }

    mutating func add(_ figure: Figure) {
        for item in figure.items {
            switch item {
            case .polyline(_, .ground): continue
            case .polyline(let points, _): for p in points { add(p, 3.5) }
            case .circle(let center, let radius, _): add(center, radius + 2)
            case .rect(let x, let y, let w, let h, _, _): add(Point(x, y), 1); add(Point(x + w, y + h), 1)
            }
        }
    }
}

// MARK: - Poses

/// A pose; nil fields come from the pattern's base pose.
struct Pose: Sendable {
    /// Torso, thigh, shin, foot, upper arm and forearm angles; `2` is the far limb.
    var t, th, sh, f, ua, fa, th2, sh2, f2, ua2, fa2: Double?
    /// How much of the arm shows, for an arm pointing at or away from the viewer.
    var aul, fal: Double?
    /// Arm angles count from the torso rather than from straight up.
    var relativeArms: Bool?
    /// The joint pinned to a point; the rest of the body hangs from it.
    var anchor: Anchor?

    init(t: Double? = nil, th: Double? = nil, sh: Double? = nil, f: Double? = nil, ua: Double? = nil, fa: Double? = nil,
         aul: Double? = nil, fal: Double? = nil, th2: Double? = nil, sh2: Double? = nil, f2: Double? = nil,
         ua2: Double? = nil, fa2: Double? = nil, ar: Bool? = nil, an: Anchor? = nil) {
        self.t = t; self.th = th; self.sh = sh; self.f = f; self.ua = ua; self.fa = fa
        self.aul = aul; self.fal = fal; self.th2 = th2; self.sh2 = sh2; self.f2 = f2
        self.ua2 = ua2; self.fa2 = fa2; self.relativeArms = ar; self.anchor = an
    }

    nonisolated(unsafe) static let angles: [WritableKeyPath<Pose, Double?>] = [\.t, \.th, \.sh, \.f, \.ua, \.fa, \.aul, \.fal, \.th2, \.sh2, \.f2, \.ua2, \.fa2]

    /// This pose with its nil fields taken from `base`.
    func over(_ base: Pose) -> Pose {
        var out = base
        for key in Pose.angles where self[keyPath: key] != nil { out[keyPath: key] = self[keyPath: key] }
        if let relativeArms { out.relativeArms = relativeArms }
        if let anchor { out.anchor = anchor }
        return out
    }

    /// The pose `u` of the way from `self` to `end`. A field the end pose lacks stays put.
    func blend(to end: Pose, _ u: Double) -> Pose {
        var out = self
        for key in Pose.angles {
            if let a = self[keyPath: key], let b = end[keyPath: key] { out[keyPath: key] = a + (b - a) * u }
        }
        if let a = anchor, let b = end.anchor {
            out.anchor = Anchor(a.joint, a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u)
        }
        return out
    }
}

struct Anchor: Sendable {
    var joint: Joint
    var x, y: Double
    init(_ joint: Joint, _ x: Double, _ y: Double) { self.joint = joint; self.x = x; self.y = y }
}

enum Joint: Sendable { case hip, shoulder, head, knee, ankle, toe, elbow, wrist, knee2, ankle2, toe2, elbow2, wrist2 }

/// Where every joint lands for a pose.
struct Joints {
    var p: [Joint: Point] = [:]
    subscript(_ j: Joint) -> Point { p[j]! }

    static let torso = 44.0, neck = 11.0, thigh = 36.0, shin = 34.0, foot = 11.0, upperArm = 25.0, forearm = 23.0

    init(_ pose: Pose) {
        func step(_ from: Point, _ angle: Double, _ length: Double) -> Point {
            from + Point(sin(angle * .pi / 180) * length, -cos(angle * .pi / 180) * length)
        }
        let t = pose.t ?? 0, th = pose.th ?? 180, sh = pose.sh ?? 180
        let arms = pose.relativeArms == true ? t : 0
        p[.hip] = Point(0, 0)
        p[.shoulder] = step(p[.hip]!, t, Self.torso)
        p[.head] = step(p[.shoulder]!, t, Self.neck)
        p[.knee] = step(p[.hip]!, th, Self.thigh)
        p[.ankle] = step(p[.knee]!, sh, Self.shin)
        p[.toe] = step(p[.ankle]!, pose.f ?? sh - 90, Self.foot)
        p[.elbow] = step(p[.shoulder]!, (pose.ua ?? 180) + arms, Self.upperArm * (pose.aul ?? 1))
        p[.wrist] = step(p[.elbow]!, (pose.fa ?? 180) + arms, Self.forearm * (pose.fal ?? 1))
        if let th2 = pose.th2, let sh2 = pose.sh2 {
            p[.knee2] = step(p[.hip]!, th2, Self.thigh)
            p[.ankle2] = step(p[.knee2]!, sh2, Self.shin)
            p[.toe2] = step(p[.ankle2]!, pose.f2 ?? sh2 - 90, Self.foot)
        }
        if let ua2 = pose.ua2, let fa2 = pose.fa2 {
            p[.elbow2] = step(p[.shoulder]!, ua2 + arms, Self.upperArm)
            p[.wrist2] = step(p[.elbow2]!, fa2 + arms, Self.forearm)
        }
        let anchor = pose.anchor ?? Anchor(.ankle, 80, Figure.ground)
        let offset = Point(anchor.x - p[anchor.joint]!.x, anchor.y - p[anchor.joint]!.y)
        for key in p.keys { p[key] = p[key]! + offset }
    }
}

// MARK: - Patterns

struct Pattern: Sendable {
    enum View: Sendable { case side(SidePattern), front(FrontPattern) }
    var family: MovementFamily
    var isHold = false
    var view: View
}

typealias Extra = @Sendable (Joints, Pose, Equipment, inout Figure) -> Void

/// A side view: the figure faces right.
struct SidePattern: Sendable {
    var base: Pose
    var start: Pose
    var end: Pose
    /// Fixed things drawn behind the figure.
    var scene: (@Sendable (inout Figure) -> Void)?
    /// A bench under the torso.
    var bench = false
    /// The weight and anything that moves with the figure.
    var extra: Extra?

    func pose(at u: Double) -> Pose { start.over(base).blend(to: end.over(base), u) }

    func figure(at u: Double, equipment: Equipment) -> Figure {
        let pose = pose(at: u), j = Joints(pose)
        var fig = Figure()
        fig.line(Point(6, Figure.ground), Point(154, Figure.ground), .ground)
        scene?(&fig)
        if bench { Draw.bench(j, pose, &fig) }
        if j.p[.knee2] != nil { fig.items.append(.polyline([j[.hip], j[.knee2], j[.ankle2], j[.toe2]], .ghost)) }
        if j.p[.elbow2] != nil { fig.items.append(.polyline([j[.shoulder], j[.elbow2], j[.wrist2]], .ghost)) }
        fig.items.append(.polyline([j[.toe], j[.ankle], j[.knee], j[.hip], j[.shoulder]], .body))
        fig.circle(j[.head], 7.5, .head)
        fig.items.append(.polyline([j[.shoulder], j[.elbow], j[.wrist]], .limb))
        extra?(j, pose, equipment, &fig)
        return fig
    }
}

/// A front view, for movements that happen out to the sides (lateral raises).
struct FrontPattern: Sendable {
    struct Params: Sendable {
        /// Arm angle out from the side, extra elbow bend, shoulder lift, knee spread, twist.
        var a = 0.0, e = 0.0, sy = 0.0, k = 0.0, tw = 0.0
        func blend(to end: Params, _ u: Double) -> Params {
            func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * u }
            return Params(a: m(a, end.a), e: m(e, end.e), sy: m(sy, end.sy), k: m(k, end.k), tw: m(tw, end.tw))
        }
    }
    enum Kind: Sendable { case standing, barbellAtHands, seatedAbduction, seatedAdduction, seatedTwist }
    var kind: Kind
    var start: Params
    var end: Params

    func figure(at u: Double, equipment: Equipment) -> Figure {
        let p = start.blend(to: end, u), cx = 80.0, g = Figure.ground
        var fig = Figure()
        fig.line(Point(6, g), Point(154, g), .ground)
        switch kind {
        case .seatedTwist:
            let hipY = 138.0, shY = 96.0, hands = Point(cx + p.tw * 30, 114)
            fig.line(Point(cx, hipY), Point(cx, shY), .body)
            fig.circle(Point(cx, shY - 11), 7.5, .head)
            for s in [-1.0, 1.0] {
                fig.items.append(.polyline([Point(cx + s * 8, hipY), Point(cx + s * 14, 118), Point(cx + s * 20, 140)], .limb))
            }
            fig.items.append(.polyline([Point(cx - 12, shY + 2), hands, Point(cx + 12, shY + 2)], .limb))
            Draw.load(equipment == .bodyweight ? .other : equipment, at: hands, &fig)
        case .seatedAbduction, .seatedAdduction:
            let hipY = 110.0, shY = hipY - 44
            fig.rect(cx - 30, hipY + 4, 60, 8, .sceneFill)
            fig.line(Point(cx - 22, hipY - 50), Point(cx - 22, hipY + 4), .sceneThin)
            fig.line(Point(cx + 22, hipY - 50), Point(cx + 22, hipY + 4), .sceneThin)
            for s in [-1.0, 1.0] {
                let knee = Point(cx + s * p.k, hipY + 12)
                fig.items.append(.polyline([Point(cx + s * 8, hipY), knee, Point(cx + s * p.k, g), Point(cx + s * (p.k + 7), g)], .limb))
                let padX = kind == .seatedAbduction ? knee.x + s * 4 : knee.x - s * 10
                fig.rect(padX - 3, knee.y - 8, 6, 16, .accent, r: 3)
            }
            Self.torso(cx, hipY, shY, &fig)
            for s in [-1.0, 1.0] {
                fig.items.append(.polyline([Point(cx + s * 15, shY), Point(cx + s * 20, shY + 24), Point(cx + s * 22, hipY)], .limb))
            }
        case .standing, .barbellAtHands:
            let hipY = 78.0, shY = hipY - 44 + p.sy
            for s in [-1.0, 1.0] {
                fig.items.append(.polyline([Point(cx + s * 8, hipY), Point(cx + s * 10, hipY + 34), Point(cx + s * 11, g), Point(cx + s * 18, g)], .limb))
            }
            Self.torso(cx, hipY, shY, &fig)
            var hands: [Point] = []
            for s in [-1.0, 1.0] {
                let shoulder = Point(cx + s * 15, shY), r = Double.pi / 180
                let elbow = shoulder + Point(s * sin(p.a * r) * 25, cos(p.a * r) * 25)
                let wrist = elbow + Point(s * sin((p.a + p.e) * r) * 23, cos((p.a + p.e) * r) * 23)
                fig.items.append(.polyline([shoulder, elbow, wrist], .limb))
                hands.append(wrist)
            }
            if kind == .barbellAtHands || equipment == .barbell {
                fig.line(hands[0] + Point(-14, 0), hands[1] + Point(14, 0), .lever)
                fig.rect(hands[0].x - 20, hands[0].y - 10, 5, 20, .accent, r: 1.5)
                fig.rect(hands[1].x + 15, hands[1].y - 10, 5, 20, .accent, r: 1.5)
            } else if equipment == .cable {
                Draw.cable(from: Point(150, 140), to: hands[1], &fig)
                for h in hands { fig.circle(h, 3.4, .accent) }
            } else if equipment == .machine {
                for h in hands { fig.rect(h.x - 4, h.y - 26, 8, 18, .accent, r: 3) }
            } else {
                for h in hands { fig.rect(h.x - 4, h.y - 2, 8, 12, .accent) }
            }
        }
        return fig
    }

    private static func torso(_ cx: Double, _ hipY: Double, _ shY: Double, _ fig: inout Figure) {
        fig.line(Point(cx, hipY), Point(cx, shY + 2), .body)
        fig.line(Point(cx - 15, shY), Point(cx + 15, shY), .body)
        fig.line(Point(cx - 8, hipY), Point(cx + 8, hipY), .body)
        fig.circle(Point(cx, shY - 12), 7.5, .head)
    }
}

/// Shared pieces of scenery and equipment.
enum Draw {
    static func step(_ from: Point, _ angle: Double, _ length: Double) -> Point {
        from + Point(sin(angle * .pi / 180) * length, -cos(angle * .pi / 180) * length)
    }

    /// The weight held at a point, drawn by equipment: a plate seen end on for a bar, a
    /// dumbbell, a kettlebell, or a handle for cables and machines.
    static func load(_ equipment: Equipment, at w: Point, _ fig: inout Figure) {
        switch equipment {
        case .barbell, .smith, .other:
            fig.circle(w, 12, .plate)
            fig.circle(w, 2.6, .accent)
        case .dumbbell:
            fig.rect(w.x - 7, w.y - 4.5, 14, 9, .accent, r: 3)
            fig.rect(w.x - 9, w.y - 6, 4, 12, .accent, r: 1.5)
            fig.rect(w.x + 5, w.y - 6, 4, 12, .accent, r: 1.5)
        case .kettlebell:
            fig.line(w, w + Point(0, 5), .lever)
            fig.circle(w + Point(0, 11), 7, .accent)
        case .cable, .machine, .band:
            fig.circle(w, 3.4, .accent)
        case .bodyweight:
            break
        }
    }

    /// A pad along the back of the torso (seat backs, benches).
    static func pad(_ j: Joints, _ p: Pose, below: Double = 8, above: Double = 14, offset: Double = 7, _ fig: inout Figure) {
        let t = p.t ?? 0, o = step(Point(0, 0), t - 90, offset)
        fig.line(step(j[.hip] + o, t, -below), step(j[.shoulder] + o, t, above), .scene)
    }

    static func bench(_ j: Joints, _ p: Pose, _ fig: inout Figure) {
        let t = p.t ?? 0, o = step(Point(0, 0), t - 90, 7)
        let a = step(j[.hip] + o, t, -14), b = step(j[.shoulder] + o, t, 16)
        fig.line(a, b, .scene)
        for end in [a, b] where end.y < Figure.ground - 6 {
            fig.line(end + Point(0, 3), Point(end.x, Figure.ground), .sceneThin)
        }
    }

    static func seat(_ j: Joints, _ fig: inout Figure) {
        let h = j[.hip]
        fig.line(h + Point(-16, 7), h + Point(12, 7), .scene)
        fig.line(h + Point(-4, 9), Point(h.x - 4, Figure.ground), .sceneThin)
    }

    static func cable(from: Point, to: Point, _ fig: inout Figure) {
        fig.circle(from, 4, .sceneFill)
        fig.line(from, to, .cable)
    }

    static func rails(_ x: Double, _ fig: inout Figure) { fig.line(Point(x, 8), Point(x, Figure.ground), .sceneThin) }

    static func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ fig: inout Figure) { fig.rect(x, y, w, h, .sceneFill, r: 3) }

    static func bar(_ x1: Double, _ x2: Double, _ y: Double, _ fig: inout Figure) {
        fig.line(Point(x1, y), Point(x2, y), .scene)
        fig.line(Point(x1 + 4, y), Point(x1 + 4, Figure.ground), .sceneThin)
        fig.line(Point(x2 - 4, y), Point(x2 - 4, Figure.ground), .sceneThin)
    }

    static func roller(_ p: Point, _ fig: inout Figure) { fig.circle(p, 5, .sceneFill) }
}
