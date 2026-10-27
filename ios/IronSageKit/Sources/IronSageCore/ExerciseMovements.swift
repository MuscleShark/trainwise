import Foundation

// The movement drawn for each built-in exercise, and each movement's two key poses.
// See ExerciseVisuals.swift for how poses are read. A new built-in exercise needs a line
// in `movementBySlug`, usually pointing at an existing movement.

extension ExerciseVisuals {
    /// Built-in exercise slug (backend/catalog.py) → movement.
    static let movementBySlug: [String: String] = [
        // Chest
        "barbell_bench_press": "bench", "dumbbell_bench_press": "bench", "smith_bench_press": "bench", "close_grip_bench_press": "bench",
        "incline_barbell_bench_press": "incline_bench", "incline_dumbbell_bench_press": "incline_bench", "smith_incline_bench_press": "incline_bench",
        "decline_barbell_bench_press": "decline_bench", "decline_dumbbell_bench_press": "decline_bench", "floor_press": "floor_press",
        "machine_chest_press": "chest_press", "incline_machine_chest_press": "chest_press", "iso_lateral_chest_press": "chest_press",
        "dumbbell_fly": "fly", "incline_dumbbell_fly": "incline_fly", "pec_deck": "pec_deck", "cable_fly": "cable_fly",
        "low_to_high_cable_fly": "low_cable_fly", "push_up": "push_up", "chest_dip": "chest_dip",
        // Back
        "deadlift": "deadlift", "trap_bar_deadlift": "deadlift", "sumo_deadlift": "sumo", "rack_pull": "rack_pull",
        "romanian_deadlift": "rdl", "stiff_leg_deadlift": "rdl", "good_morning": "good_morning",
        "barbell_row": "row", "pendlay_row": "row", "t_bar_row": "row", "meadows_row": "row", "dumbbell_row": "row",
        "chest_supported_dumbbell_row": "row_pad", "seal_row": "row_pad",
        "seated_cable_row": "seated_row", "single_arm_cable_row": "seated_row", "machine_row": "seated_row", "iso_lateral_row": "seated_row",
        "lat_pulldown": "pulldown", "close_grip_lat_pulldown": "pulldown", "single_arm_lat_pulldown": "pulldown", "iso_lateral_high_row": "pulldown",
        "straight_arm_pulldown": "straight_pulldown", "dumbbell_pullover": "pullover",
        "pull_up": "pull_up", "chin_up": "pull_up", "assisted_pull_up": "assisted_pull_up", "inverted_row": "inverted_row",
        "back_extension": "back_extension", "reverse_hyperextension": "reverse_hyper",
        "barbell_shrug": "shrug", "dumbbell_shrug": "shrug", "face_pull": "face_pull",
        // Shoulders
        "overhead_press": "ohp", "push_press": "push_press", "seated_barbell_press": "seated_press", "dumbbell_shoulder_press": "seated_press",
        "arnold_press": "seated_press", "machine_shoulder_press": "seated_press", "iso_lateral_shoulder_press": "seated_press",
        "smith_shoulder_press": "seated_press", "landmine_press": "landmine",
        "lateral_raise": "lateral_raise", "cable_lateral_raise": "lateral_raise", "machine_lateral_raise": "lateral_raise",
        "front_raise": "front_raise", "rear_delt_fly": "rear_fly", "cable_rear_delt_fly": "rear_fly", "reverse_pec_deck": "reverse_pec_deck",
        "upright_row": "upright_row",
        // Biceps and forearms
        "barbell_curl": "curl", "ez_bar_curl": "curl", "dumbbell_curl": "curl", "hammer_curl": "curl", "cable_curl": "curl",
        "rope_hammer_curl": "curl", "reverse_curl": "curl", "incline_dumbbell_curl": "incline_curl", "concentration_curl": "concentration_curl",
        "preacher_curl": "preacher_curl", "machine_preacher_curl": "preacher_curl", "bayesian_curl": "bayesian_curl", "wrist_curl": "wrist_curl",
        // Triceps
        "tricep_pushdown": "pushdown", "machine_tricep_extension": "pushdown",
        "overhead_cable_tricep_extension": "overhead_extension", "dumbbell_overhead_tricep_extension": "overhead_extension",
        "skull_crusher": "skull_crusher", "dumbbell_skull_crusher": "skull_crusher", "dumbbell_kickback": "kickback",
        "tricep_dip": "dip", "bench_dip": "bench_dip",
        // Quads, glutes and hamstrings
        "back_squat": "squat", "safety_bar_squat": "squat", "smith_squat": "squat", "box_squat": "box_squat",
        "front_squat": "front_squat", "goblet_squat": "goblet_squat", "hack_squat": "machine_squat", "pendulum_squat": "machine_squat",
        "belt_squat": "belt_squat", "leg_press": "leg_press", "single_leg_press": "leg_press",
        "bulgarian_split_squat": "bulgarian_split_squat", "walking_lunge": "lunge", "reverse_lunge": "lunge", "smith_lunge": "lunge",
        "step_up": "step_up", "leg_extension": "leg_extension", "lying_leg_curl": "lying_leg_curl", "seated_leg_curl": "seated_leg_curl",
        "nordic_curl": "nordic", "glute_ham_raise": "nordic",
        "dumbbell_romanian_deadlift": "rdl", "single_leg_romanian_deadlift": "single_leg_rdl",
        "hip_thrust": "hip_thrust", "machine_hip_thrust": "hip_thrust", "glute_bridge": "glute_bridge",
        "cable_glute_kickback": "glute_kickback", "machine_glute_kickback": "glute_kickback",
        "hip_abduction": "hip_abduction", "hip_adduction": "hip_adduction", "kettlebell_swing": "kettlebell_swing", "sled_push": "sled_push",
        // Calves
        "standing_calf_raise": "calf_raise", "smith_calf_raise": "calf_raise", "seated_calf_raise": "seated_calf_raise",
        "leg_press_calf_raise": "leg_press_calf_raise",
        // Core
        "plank": "plank", "side_plank": "plank", "hollow_hold": "hollow_hold", "dead_bug": "dead_bug", "crunch": "crunch",
        "decline_sit_up": "decline_sit_up", "leg_raise": "leg_raise", "hanging_leg_raise": "hanging_leg_raise",
        "hanging_knee_raise": "hanging_knee_raise", "ab_wheel_rollout": "ab_wheel", "cable_crunch": "cable_crunch",
        "machine_crunch": "machine_crunch", "russian_twist": "russian_twist", "pallof_press": "pallof_press",
        // Full body
        "power_clean": "clean", "hang_clean": "hang_clean", "farmers_carry": "carry",
    ]

    static let patterns: [String: Pattern] = {
        var all: [String: Pattern] = [:]
        func side(_ name: String, _ family: MovementFamily, hold: Bool = false, base: Pose, _ start: Pose, _ end: Pose,
                  bench: Bool = false, scene: (@Sendable (inout Figure) -> Void)? = nil, extra: Extra? = nil) {
            all[name] = Pattern(family: family, isHold: hold, view: .side(SidePattern(base: base, start: start, end: end, scene: scene, bench: bench, extra: extra)))
        }
        func front(_ name: String, _ family: MovementFamily, _ kind: FrontPattern.Kind, _ start: FrontPattern.Params, _ end: FrontPattern.Params) {
            all[name] = Pattern(family: family, view: .front(FrontPattern(kind: kind, start: start, end: end)))
        }
        let g = Figure.ground
        let standing = Pose(t: 0, th: 180, sh: 180, ua: 180, fa: 180, an: Anchor(.ankle, 80, g))
        func st(_ p: Pose = Pose()) -> Pose { p.over(standing) }
        func stAt(_ x: Double) -> Pose { st(Pose(an: Anchor(.ankle, x, g))) }
        let seated = Pose(t: -4, th: 92, sh: 182, an: Anchor(.hip, 62, 110))
        let lying = Pose(t: 270, th: 65, sh: 190, ar: true, an: Anchor(.hip, 96, 124))
        let incline = Pose(t: 300, an: Anchor(.hip, 100, 124)).over(lying)

        // Loads and props, shared by several movements.
        let atWrist: Extra = { j, _, eq, fig in Draw.load(eq, at: j[.wrist], &fig) }
        let onUpperBack: Extra = { j, p, eq, fig in
            if eq == .smith { Draw.rails(j[.shoulder].x - 4, &fig) }
            Draw.load(eq == .bodyweight ? .barbell : eq, at: Draw.step(j[.shoulder], (p.t ?? 0) - 90, 5), &fig)
        }
        func cableAtWrist(from: Point) -> Extra {
            { j, _, eq, fig in
                if eq == .cable { Draw.cable(from: from, to: j[.wrist], &fig) }
                Draw.load(eq, at: j[.wrist], &fig)
            }
        }
        let benchAtWrist: Extra = { j, _, eq, fig in
            if eq == .smith { Draw.rails(j[.wrist].x, &fig) }
            Draw.load(eq, at: j[.wrist], &fig)
        }

        // Squats
        side("squat", .squat, base: st(Pose(ua: 215, fa: 20, ar: true, an: Anchor(.ankle, 84, g))),
             Pose(t: 0), Pose(t: 40, th: 100, sh: 200), extra: onUpperBack)
        side("box_squat", .squat, base: st(Pose(ua: 215, fa: 20, ar: true, an: Anchor(.ankle, 84, g))),
             Pose(t: 0), Pose(t: 40, th: 100, sh: 200), scene: { Draw.box(42, 116, 30, 30, &$0) }, extra: onUpperBack)
        side("front_squat", .squat, base: stAt(84), Pose(t: 0, ua: 95, fa: 310), Pose(t: 28, th: 100, sh: 205, ua: 105, fa: 318),
             extra: { j, p, eq, fig in Draw.load(eq, at: Draw.step(j[.shoulder], (p.t ?? 0) + 90, 8), &fig) })
        side("goblet_squat", .squat, base: stAt(84), Pose(t: 0, ua: 160, fa: 10), Pose(t: 25, th: 100, sh: 205, ua: 168, fa: 22), extra: atWrist)
        side("machine_squat", .squat, base: st(Pose(ua: 200, fa: 350, an: Anchor(.ankle, 92, g))),
             Pose(t: -18, th: 180, sh: 168), Pose(t: 6, th: 97, sh: 205),
             scene: { $0.line(Point(18, 40), Point(60, g), .sceneThin) },
             extra: { j, p, _, fig in
                 Draw.pad(j, p, below: 4, above: 10, offset: 8, &fig)
                 fig.circle(Draw.step(j[.shoulder], (p.t ?? 0) + 90, 6), 4, .accent)
             })
        side("belt_squat", .squat, base: st(Pose(ua: 115, fa: 95, an: Anchor(.ankle, 84, g))), Pose(t: 0), Pose(t: 20, th: 100, sh: 203),
             extra: { j, _, _, fig in
                 fig.line(j[.hip], j[.hip] + Point(4, 22), .cable)
                 fig.circle(j[.hip] + Point(4, 30), 8, .plate)
             })
        side("leg_press", .legPress, base: Pose(t: 300, th: 0, sh: 120, ua: 180, fa: 120, an: Anchor(.hip, 62, 124)),
             Pose(), Pose(th: 42, sh: 48),
             extra: { j, p, _, fig in
                 Draw.pad(j, p, below: 6, above: 16, offset: 8, &fig)
                 fig.line(j[.ankle] + Point(-9, -9), j[.ankle] + Point(10, 10), .lever)
                 fig.line(j[.hip] + Point(-4, 8), Point(j[.hip].x - 4, g), .sceneThin)
             })

        // Lunges
        side("lunge", .lunge, base: Pose(t: 4, ua: 180, fa: 180, an: Anchor(.ankle, 96, g)),
             Pose(th: 160, sh: 185, th2: 195, sh2: 210), Pose(th: 95, sh: 190, th2: 175, sh2: 280), extra: atWrist)
        side("bulgarian_split_squat", .lunge, base: Pose(t: 8, ua: 180, fa: 180, sh2: 270, an: Anchor(.ankle, 100, g)),
             Pose(th: 165, sh: 182, th2: 210), Pose(th: 100, sh: 192, th2: 180),
             scene: { Draw.box(8, 112, 34, 34, &$0) }, extra: atWrist)
        side("step_up", .lunge, base: Pose(t: 10, ua: 180, fa: 180, an: Anchor(.ankle, 96, 120)),
             Pose(th: 110, sh: 200, th2: 200, sh2: 200), Pose(t: 0, th: 180, sh: 182, th2: 185, sh2: 200),
             scene: { Draw.box(84, 120, 52, 26, &$0) }, extra: atWrist)

        // Hinges and power
        side("deadlift", .hinge, base: stAt(76), Pose(t: 70, th: 120, sh: 190), Pose(), extra: atWrist)
        side("sumo", .hinge, base: stAt(76), Pose(t: 48, th: 108, sh: 203), Pose(), extra: atWrist)
        side("rack_pull", .hinge, base: stAt(76), Pose(t: 42, th: 160, sh: 186), Pose(),
             scene: { $0.rect(110, 112, 6, 34, .sceneFill) }, extra: atWrist)
        side("rdl", .hinge, base: stAt(80), Pose(), Pose(t: 80, th: 165, sh: 190), extra: atWrist)
        side("single_leg_rdl", .hinge, base: stAt(92), Pose(th2: 186, sh2: 200), Pose(t: 80, th: 170, sh: 188, th2: 262, sh2: 265), extra: atWrist)
        side("good_morning", .hinge, base: st(Pose(ua: 215, fa: 20, ar: true, an: Anchor(.ankle, 80, g))),
             Pose(), Pose(t: 75, th: 168, sh: 188), extra: onUpperBack)
        side("clean", .power, base: stAt(76), Pose(t: 70, th: 120, sh: 190), Pose(th: 168, sh: 190, ua: 100, fa: 308), extra: atWrist)
        side("hang_clean", .power, base: stAt(76), Pose(t: 35, th: 165, sh: 190), Pose(th: 168, sh: 190, ua: 100, fa: 308), extra: atWrist)
        side("kettlebell_swing", .power, base: stAt(84), Pose(t: 62, th: 150, sh: 195, ua: 198, fa: 198), Pose(ua: 92, fa: 90), extra: atWrist)

        // Rows and pulls
        let bentOver = st(Pose(t: 70, th: 160, sh: 190, an: Anchor(.ankle, 78, g)))
        side("row", .row, base: bentOver, Pose(), Pose(ua: 255, fa: 175), extra: atWrist)
        side("row_pad", .row, base: st(Pose(t: 55, th: 165, sh: 190, an: Anchor(.ankle, 60, g))), Pose(), Pose(ua: 250, fa: 178),
             extra: { j, p, eq, fig in
                 let t = p.t ?? 0, o = Draw.step(Point(0, 0), t + 90, 8)
                 fig.line(Draw.step(j[.hip] + o, t, 8), Draw.step(j[.shoulder] + o, t, 10), .scene)
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        side("seated_row", .row, base: Pose(th: 80, sh: 95, an: Anchor(.hip, 52, 128)),
             Pose(t: 22, ua: 80, fa: 86), Pose(t: -6, ua: 218, fa: 96),
             scene: { fig in
                 Draw.box(30, 134, 36, 12, &fig)
                 fig.line(Point(128, 96), Point(128, 140), .scene)
             },
             extra: { j, _, eq, fig in
                 if eq == .cable { Draw.cable(from: Point(150, 116), to: j[.wrist], &fig) } else { fig.line(Point(142, 30), j[.wrist], .lever) }
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        side("face_pull", .row, base: st(Pose(t: -4, an: Anchor(.ankle, 64, g))), Pose(ua: 72, fa: 72), Pose(ua: 300, fa: 68),
             extra: { j, _, eq, fig in
                 Draw.cable(from: Point(152, 38), to: j[.wrist], &fig)
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        side("inverted_row", .row, base: Pose(f: 30, an: Anchor(.wrist, 118, 62)),
             Pose(t: 72, th: 252, sh: 252, ua: 0, fa: 0), Pose(t: 47, th: 227, sh: 227, ua: 225, fa: 20),
             scene: { Draw.bar(100, 140, 62, &$0) })
        side("pulldown", .verticalPull, base: seated, Pose(t: -6, ua: 4, fa: 4), Pose(t: -14, ua: 196, fa: 14),
             extra: { j, _, eq, fig in
                 Draw.seat(j, &fig)
                 Draw.roller(j[.knee] + Point(-4, -8), &fig)
                 if eq == .machine { fig.line(Point(30, 12), j[.wrist], .lever) } else { Draw.cable(from: Point(66, 6), to: j[.wrist], &fig) }
                 fig.line(j[.wrist] + Point(-12, 0), j[.wrist] + Point(12, 0), .lever)
             })
        side("straight_pulldown", .verticalPull, base: st(Pose(t: 24, th: 170, sh: 186, an: Anchor(.ankle, 58, g))),
             Pose(ua: 36, fa: 36), Pose(ua: 186, fa: 186),
             extra: { j, _, eq, fig in
                 Draw.cable(from: Point(140, 10), to: j[.wrist], &fig)
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        side("pullover", .verticalPull, base: lying, Pose(ua: 90, fa: 90), Pose(ua: 15, fa: 20), bench: true, extra: atWrist)
        let pullUpBar: @Sendable (inout Figure) -> Void = { $0.line(Point(44, 24), Point(116, 24), .scene) }
        side("pull_up", .verticalPull, base: Pose(t: 0, th: 186, sh: 205, an: Anchor(.wrist, 80, 24)),
             Pose(ua: 0, fa: 0), Pose(t: -8, ua: 194, fa: 8), scene: pullUpBar)
        side("assisted_pull_up", .verticalPull, base: Pose(t: 0, th: 180, sh: 270, an: Anchor(.wrist, 80, 24)),
             Pose(ua: 0, fa: 0), Pose(t: -8, ua: 194, fa: 8), scene: pullUpBar,
             extra: { j, _, _, fig in
                 fig.line(j[.knee] + Point(-10, 4), j[.knee] + Point(14, 4), .scene)
                 fig.line(j[.knee] + Point(2, 4), Point(j[.knee].x + 2, g), .sceneThin)
             })
        side("back_extension", .backExtension, base: Pose(th: 225, sh: 225, ua: 160, fa: 20, ar: true, an: Anchor(.hip, 84, 92)),
             Pose(t: 150), Pose(t: 45),
             scene: { fig in
                 fig.line(Point(74, 98), Point(92, 90), .scene)
                 fig.line(Point(84, 98), Point(64, g), .sceneThin)
                 Draw.roller(Point(44, 136), &fig)
             })
        side("reverse_hyper", .backExtension, base: Pose(t: 90, ua: 180, fa: 180, an: Anchor(.hip, 78, 96)),
             Pose(th: 176, sh: 180), Pose(th: 262, sh: 262),
             scene: { fig in
                 fig.line(Point(74, 106), Point(128, 106), .scene)
                 fig.line(Point(118, 108), Point(118, g), .sceneThin)
             })

        // Presses
        side("bench", .press, base: lying, Pose(ua: 290, fa: 90, aul: 0.45), Pose(ua: 90, fa: 90, aul: 1), bench: true, extra: benchAtWrist)
        side("incline_bench", .press, base: incline, Pose(ua: 290, fa: 60, aul: 0.45), Pose(ua: 60, fa: 60, aul: 1), bench: true, extra: benchAtWrist)
        side("decline_bench", .press, base: Pose(t: 252, th: 80, sh: 150, an: Anchor(.hip, 100, 112)).over(lying),
             Pose(ua: 290, fa: 108, aul: 0.45), Pose(ua: 108, fa: 108, aul: 1), bench: true, extra: atWrist)
        side("floor_press", .press, base: Pose(t: 270, th: 48, sh: 172, ar: true, an: Anchor(.hip, 96, 140)),
             Pose(ua: 290, fa: 90, aul: 0.3), Pose(ua: 90, fa: 90, aul: 1), extra: atWrist)
        side("chest_press", .press, base: seated, Pose(ua: 205, fa: 90, aul: 0.5), Pose(ua: 92, fa: 92, aul: 1),
             extra: { j, p, eq, fig in
                 Draw.seat(j, &fig)
                 Draw.pad(j, p, below: 2, above: 16, &fig)
                 fig.line(Point(120, 20), j[.wrist], .lever)
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        side("push_up", .pushUp, base: Pose(f: 200, an: Anchor(.wrist, 116, g)),
             Pose(t: 74, th: 254, sh: 254, ua: 300, fa: 150), Pose(t: 65, th: 245, sh: 245, ua: 180, fa: 180))
        let dipBars: @Sendable (inout Figure) -> Void = { Draw.bar(70, 124, 86, &$0) }
        side("dip", .dip, base: Pose(th: 172, sh: 212, an: Anchor(.wrist, 92, 84)),
             Pose(t: 8, ua: 180, fa: 180), Pose(t: 14, ua: 265, fa: 150), scene: dipBars)
        side("chest_dip", .dip, base: Pose(th: 168, sh: 208, an: Anchor(.wrist, 92, 84)),
             Pose(t: 22, ua: 180, fa: 180), Pose(t: 32, ua: 268, fa: 150), scene: dipBars)
        side("bench_dip", .dip, base: Pose(t: 0, an: Anchor(.wrist, 44, 108)),
             Pose(th: 90, sh: 145, ua: 190, fa: 190), Pose(th: 60, sh: 150, ua: 280, fa: 160),
             scene: { Draw.box(10, 108, 40, 38, &$0) })
        side("ohp", .overheadPress, base: stAt(80), Pose(ua: 150, fa: 10, aul: 0.7), Pose(ua: 0, fa: 0, aul: 1), extra: atWrist)
        side("push_press", .overheadPress, base: stAt(80), Pose(th: 168, sh: 194, ua: 150, fa: 10, aul: 0.7), Pose(ua: 0, fa: 0, aul: 1), extra: atWrist)
        side("seated_press", .overheadPress, base: Pose(t: 0).over(seated), Pose(ua: 150, fa: 10, aul: 0.7), Pose(ua: 0, fa: 0, aul: 1),
             extra: { j, p, eq, fig in
                 Draw.seat(j, &fig)
                 Draw.pad(j, p, below: 2, above: 18, &fig)
                 if eq == .smith { Draw.rails(j[.wrist].x, &fig) }
                 if eq == .machine { fig.line(Point(108, 4), j[.wrist], .lever) }
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        side("landmine", .overheadPress, base: st(Pose(t: 8, th: 176, sh: 184, th2: 196, sh2: 204, an: Anchor(.ankle, 72, g))),
             Pose(ua: 155, fa: 15, aul: 0.7), Pose(ua: 42, fa: 42, aul: 1),
             extra: { j, _, _, fig in
                 fig.line(Point(150, g - 2), j[.wrist], .lever)
                 fig.circle(j[.wrist], 4, .accent)
             })

        // Flies and raises
        side("fly", .fly, base: lying, Pose(ua: 300, fa: 290, aul: 0.3, fal: 0.3), Pose(ua: 90, fa: 90, aul: 1, fal: 1), bench: true, extra: atWrist)
        side("incline_fly", .fly, base: incline, Pose(ua: 300, fa: 290, aul: 0.3, fal: 0.3), Pose(ua: 60, fa: 60, aul: 1, fal: 1), bench: true, extra: atWrist)
        side("pec_deck", .fly, base: seated, Pose(ua: 95, fa: 95, aul: 0.25, fal: 0.25), Pose(ua: 95, fa: 95, aul: 1, fal: 1),
             extra: { j, p, _, fig in
                 Draw.seat(j, &fig)
                 Draw.pad(j, p, below: 2, above: 16, &fig)
                 fig.circle(j[.wrist], 3.4, .accent)
             })
        side("cable_fly", .fly, base: st(Pose(t: 14, th: 172, sh: 182, th2: 194, sh2: 200, an: Anchor(.ankle, 92, g))),
             Pose(ua: 112, fa: 112, aul: 0.3, fal: 0.3), Pose(ua: 138, fa: 138, aul: 1, fal: 1),
             extra: { j, _, eq, fig in
                 Draw.cable(from: Point(30, 22), to: j[.wrist], &fig)
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        side("low_cable_fly", .fly, base: st(Pose(t: 6, an: Anchor(.ankle, 92, g))),
             Pose(ua: 150, fa: 150, aul: 0.3, fal: 0.3), Pose(ua: 62, fa: 62, aul: 1, fal: 1),
             extra: { j, _, eq, fig in
                 Draw.cable(from: Point(30, 140), to: j[.wrist], &fig)
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        side("reverse_pec_deck", .raise, base: Pose(t: 6).over(seated),
             Pose(ua: 92, fa: 92, aul: 1, fal: 1), Pose(ua: 92, fa: 92, aul: 0.22, fal: 0.22),
             extra: { j, _, _, fig in
                 Draw.seat(j, &fig)
                 fig.line(j[.hip] + Point(10, -6), j[.shoulder] + Point(10, 4), .scene)
                 fig.circle(j[.wrist], 3.4, .accent)
             })
        side("front_raise", .raise, base: st(), Pose(ua: 176, fa: 176), Pose(ua: 92, fa: 88), extra: atWrist)
        side("rear_fly", .raise, base: bentOver, Pose(ua: 182, fa: 178), Pose(ua: 258, fa: 252), extra: cableAtWrist(from: Point(140, 140)))
        front("lateral_raise", .raise, .standing, .init(a: 10, e: 8), .init(a: 86, e: 8))
        front("upright_row", .raise, .barbellAtHands, .init(a: 8, e: -12), .init(a: 100, e: -150))
        front("shrug", .shrug, .standing, .init(a: 6), .init(a: 6, sy: -8))

        // Arms
        side("curl", .curl, base: st(), Pose(ua: 182, fa: 182), Pose(ua: 172, fa: 24), extra: cableAtWrist(from: Point(118, 142)))
        side("incline_curl", .curl, base: Pose(t: 330, th: 95, sh: 186, an: Anchor(.hip, 74, 110)), Pose(ua: 188, fa: 188), Pose(ua: 188, fa: 40),
             extra: { j, p, eq, fig in
                 Draw.pad(j, p, below: 4, above: 16, &fig)
                 fig.line(j[.hip] + Point(-6, 8), Point(j[.hip].x - 6, g), .sceneThin)
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        let seatedAtWrist: Extra = { j, _, eq, fig in
            Draw.seat(j, &fig)
            Draw.load(eq, at: j[.wrist], &fig)
        }
        side("concentration_curl", .curl, base: Pose(t: 38, th: 92).over(seated), Pose(ua: 168, fa: 168), Pose(ua: 168, fa: 18), extra: seatedAtWrist)
        side("preacher_curl", .curl, base: Pose(t: 12).over(seated), Pose(ua: 132, fa: 136), Pose(ua: 132, fa: 8),
             extra: { j, _, eq, fig in
                 Draw.seat(j, &fig)
                 fig.line(Draw.step(j[.shoulder], 132, 4), Draw.step(j[.shoulder], 132, 30), .scene)
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        side("bayesian_curl", .curl, base: st(Pose(t: 6, th: 172, sh: 182, th2: 196, sh2: 204, an: Anchor(.ankle, 92, g))),
             Pose(ua: 205, fa: 205), Pose(ua: 205, fa: 40),
             extra: { j, _, eq, fig in
                 Draw.cable(from: Point(18, 60), to: j[.wrist], &fig)
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        side("wrist_curl", .curl, base: Pose(t: 24, f: 0, ua: 162).over(seated), Pose(fa: 96), Pose(fa: 62), extra: seatedAtWrist)
        side("pushdown", .triceps, base: st(Pose(t: 10, an: Anchor(.ankle, 74, g))), Pose(ua: 176, fa: 58), Pose(ua: 178, fa: 180),
             extra: { j, _, eq, fig in
                 if eq == .machine { fig.line(Point(132, 74), j[.wrist], .lever) } else { Draw.cable(from: Point(112, 8), to: j[.wrist], &fig) }
                 Draw.load(eq, at: j[.wrist], &fig)
             })
        side("overhead_extension", .triceps, base: stAt(84), Pose(t: 4, ua: 8, fa: 196), Pose(t: 4, ua: 8, fa: 6),
             extra: cableAtWrist(from: Point(20, 130)))
        side("skull_crusher", .triceps, base: lying, Pose(ua: 70, fa: 220), Pose(ua: 70, fa: 72), bench: true, extra: atWrist)
        side("kickback", .triceps, base: st(Pose(t: 70, th: 160, sh: 190, ua: 258, an: Anchor(.ankle, 78, g))),
             Pose(fa: 180), Pose(fa: 258), extra: atWrist)

        // Leg machines
        let legMachine = Pose(t: -10, ua: 180, fa: 150, an: Anchor(.hip, 60, 104)).over(seated)
        side("leg_extension", .kneeMachine, base: legMachine, Pose(sh: 182), Pose(sh: 96),
             extra: { j, _, _, fig in
                 Draw.seat(j, &fig)
                 fig.line(j[.hip] + Point(-8, 0), j[.hip] + Point(-14, -40), .scene)
                 Draw.roller(j[.ankle] + Point(3, -2), &fig)
             })
        side("seated_leg_curl", .kneeMachine, base: legMachine, Pose(sh: 96), Pose(sh: 198),
             extra: { j, _, _, fig in
                 Draw.seat(j, &fig)
                 fig.line(j[.hip] + Point(-8, 0), j[.hip] + Point(-14, -40), .scene)
                 Draw.roller(j[.ankle] + Point(-2, 6), &fig)
                 Draw.roller(j[.knee] + Point(-4, -9), &fig)
             })
        side("lying_leg_curl", .kneeMachine, base: Pose(t: 270, th: 90, ua: 200, fa: 250, an: Anchor(.hip, 84, 118)),
             Pose(sh: 96), Pose(sh: 12),
             scene: { fig in
                 fig.line(Point(30, 126), Point(124, 126), .scene)
                 fig.line(Point(40, 128), Point(40, g), .sceneThin)
                 fig.line(Point(116, 128), Point(116, g), .sceneThin)
             },
             extra: { j, _, _, fig in Draw.roller(j[.ankle] + Point(2, -6), &fig) })
        side("nordic", .kneeMachine, base: Pose(sh: 270, an: Anchor(.knee, 84, 140)),
             Pose(t: 0, th: 180, ua: 150, fa: 150), Pose(t: 65, th: 245, ua: 118, fa: 118),
             extra: { j, _, _, fig in Draw.roller(j[.ankle] + Point(0, -7), &fig) })

        // Glutes and hips
        let atHip: Extra = { j, p, eq, fig in
            Draw.load(eq == .machine || eq == .bodyweight ? .barbell : eq, at: Draw.step(j[.hip], (p.t ?? 0) + 90, 12), &fig)
        }
        side("hip_thrust", .glute, base: Pose(ua: 150, fa: 60, an: Anchor(.shoulder, 40, 108)),
             Pose(t: 300, th: 60, sh: 170), Pose(t: 270, th: 95, sh: 180), scene: { Draw.box(8, 112, 36, 34, &$0) }, extra: atHip)
        side("glute_bridge", .glute, base: Pose(ua: 100, fa: 100, an: Anchor(.shoulder, 36, 140)),
             Pose(t: 270, th: 45, sh: 175), Pose(t: 245, th: 80, sh: 185), extra: atHip)
        side("glute_kickback", .glute, base: Pose(t: 45, th: 175, sh: 185, ua: 150, fa: 150, an: Anchor(.ankle, 96, g)),
             Pose(th2: 185, sh2: 210), Pose(th2: 250, sh2: 240),
             extra: { j, _, eq, fig in
                 if eq == .cable { Draw.cable(from: Point(16, 140), to: j[.ankle2], &fig) } else { Draw.roller(j[.ankle2], &fig) }
             })
        front("hip_abduction", .hipMachine, .seatedAbduction, .init(k: 9), .init(k: 26))
        front("hip_adduction", .hipMachine, .seatedAdduction, .init(k: 26), .init(k: 8))

        // Calves
        side("calf_raise", .calf, base: st(Pose(an: Anchor(.toe, 100, 138))), Pose(f: 90), Pose(f: 132),
             scene: { Draw.box(88, 138, 30, 8, &$0) },
             extra: { j, _, eq, fig in
                 if eq == .smith {
                     Draw.rails(j[.shoulder].x - 4, &fig)
                     Draw.load(.barbell, at: Draw.step(j[.shoulder], -90, 5), &fig)
                 } else {
                     fig.circle(j[.shoulder] + Point(-2, -5), 4.5, .accent)
                 }
             })
        side("seated_calf_raise", .calf, base: Pose(t: 0, ua: 180, fa: 150, an: Anchor(.toe, 108, 138)).over(seated),
             Pose(f: 90), Pose(f: 130), scene: { Draw.box(96, 138, 26, 8, &$0) },
             extra: { j, _, _, fig in
                 fig.line(j[.hip] + Point(-16, 7), j[.hip] + Point(8, 7), .scene)
                 fig.line(j[.knee] + Point(-10, -7), j[.knee] + Point(10, -7), .lever)
             })
        side("leg_press_calf_raise", .calf, base: Pose(t: 300, th: 44, sh: 46, ua: 180, fa: 120, an: Anchor(.hip, 62, 124)),
             Pose(f: 316), Pose(f: 350),
             extra: { j, p, _, fig in
                 let m = Draw.step(j[.ankle], p.f ?? 0, 8)
                 Draw.pad(j, p, below: 6, above: 16, offset: 8, &fig)
                 fig.line(m + Point(-10, -10), m + Point(10, 10), .lever)
             })

        // Core
        side("plank", .hold, hold: true, base: Pose(f: 200, ua: 180, fa: 90, an: Anchor(.wrist, 138, g)),
             Pose(t: 78, th: 258, sh: 258), Pose(t: 80, th: 259, sh: 259))
        side("hollow_hold", .hold, hold: true, base: Pose(ua: 285, fa: 285, an: Anchor(.hip, 84, 140)),
             Pose(t: 286, th: 75, sh: 75), Pose(t: 288, th: 73, sh: 73))
        side("dead_bug", .core, base: Pose(t: 270, th2: 0, sh2: 90, ua2: 0, fa2: 0, an: Anchor(.hip, 84, 140)),
             Pose(th: 0, sh: 90, ua: 0, fa: 0), Pose(th: 82, sh: 84, ua: 280, fa: 276))
        side("crunch", .core, base: Pose(th: 45, sh: 172, ua: 30, fa: 200, ar: true, an: Anchor(.hip, 92, 140)), Pose(t: 270), Pose(t: 302))
        side("decline_sit_up", .core, base: Pose(th: 55, sh: 150, ua: 30, fa: 200, ar: true, an: Anchor(.hip, 90, 116)),
             Pose(t: 248), Pose(t: 350),
             scene: { fig in
                 fig.line(Point(22, 142), Point(104, 116), .scene)
                 fig.line(Point(96, 119), Point(96, g), .sceneThin)
             },
             extra: { j, _, _, fig in Draw.roller(j[.ankle] + Point(2, -7), &fig) })
        side("leg_raise", .core, base: Pose(t: 270, ua: 90, fa: 90, an: Anchor(.hip, 70, 140)), Pose(th: 86, sh: 86), Pose(th: 6, sh: 6))
        let hangingBar: @Sendable (inout Figure) -> Void = { $0.line(Point(40, 24), Point(110, 24), .scene) }
        side("hanging_leg_raise", .core, base: Pose(t: 0, th: 180, sh: 180, ua: 0, fa: 0, an: Anchor(.wrist, 72, 24)),
             Pose(), Pose(t: -12, th: 84, sh: 86), scene: hangingBar)
        side("hanging_knee_raise", .core, base: Pose(t: 0, th: 180, sh: 180, ua: 0, fa: 0, an: Anchor(.wrist, 72, 24)),
             Pose(), Pose(t: -8, th: 70, sh: 172), scene: hangingBar)
        side("ab_wheel", .core, base: Pose(sh: 270, an: Anchor(.knee, 36, g)),
             Pose(t: 60, th: 165, ua: 155, fa: 155), Pose(t: 78, th: 235, ua: 108, fa: 108),
             extra: { j, _, _, fig in fig.circle(Point(j[.wrist].x, 139), 7, .plate) })
        side("cable_crunch", .core, base: Pose(th: 180, sh: 270, ua: 130, fa: 10, ar: true, an: Anchor(.knee, 100, g)),
             Pose(t: 10), Pose(t: 92),
             extra: { j, _, _, fig in Draw.cable(from: Point(112, 6), to: j[.wrist], &fig) })
        side("machine_crunch", .core, base: Pose(ua: 150, fa: 30, ar: true).over(seated), Pose(t: -4), Pose(t: 52),
             extra: { j, p, _, fig in
                 Draw.seat(j, &fig)
                 fig.circle(Draw.step(j[.shoulder], (p.t ?? 0) + 90, 8), 4, .accent)
             })
        side("pallof_press", .core, base: stAt(74), Pose(ua: 180, fa: 90, aul: 0.5), Pose(ua: 90, fa: 90, aul: 1),
             extra: { j, _, _, fig in
                 Draw.cable(from: Point(152, 96), to: j[.wrist], &fig)
                 fig.circle(j[.wrist], 3.4, .accent)
             })
        front("russian_twist", .core, .seatedTwist, .init(tw: -1), .init(tw: 1))

        // Carries and sleds
        side("carry", .carry, base: Pose(t: 0, ua: 180, fa: 180, an: Anchor(.hip, 80, 78)),
             Pose(th: 162, sh: 186, th2: 198, sh2: 205), Pose(th: 198, sh: 205, th2: 162, sh2: 186), extra: atWrist)
        side("sled_push", .carry, base: Pose(t: 56, ua: 72, fa: 72, an: Anchor(.hip, 62, 92)),
             Pose(th: 150, sh: 205, th2: 212, sh2: 232), Pose(th: 212, sh: 232, th2: 150, sh2: 205),
             extra: { j, _, _, fig in
                 fig.line(j[.wrist], Point(j[.wrist].x + 4, g - 6), .lever)
                 fig.rect(j[.wrist].x - 8, g - 12, 34, 10, .sceneFill)
             })
        return all
    }()
}
