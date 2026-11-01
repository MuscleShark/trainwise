import Foundation

/// What a built-in program is for and how to progress on it, shown on its page.
/// Keyed by the program's slug in backend/template_catalog.py, like the exercise
/// figures; a new built-in program needs an entry here (a test checks).
public struct ProgramGuide: Sendable, Hashable {
    public enum Goal: String, Sendable, Hashable {
        case strength, muscle, strengthAndMuscle, allRound, quick
    }

    public let goal: Goal
    let whoEn: String
    let whoZh: String
    let progressEn: String
    let progressZh: String

    /// Who the program suits, in a sentence.
    public func who(chinese: Bool) -> String { chinese ? whoZh : whoEn }

    /// How to add weight or reps on it.
    public func progress(chinese: Bool) -> String { chinese ? progressZh : progressEn }

    /// The guide for a built-in program, by its ID.
    public static func forTemplate(_ id: UUID) -> ProgramGuide? {
        byID[id]
    }

    /// The ID the API gives a built-in program: a version 5 UUID of its slug.
    public static func builtinID(slug: String) -> UUID {
        UUID(version5: namespace, name: "template:\(slug)")
    }

    private static let namespace = UUID(uuidString: "2d7e5c1a-8b44-4f6e-9c3d-7a1b0e5f9d22")!
    private static let byID = Dictionary(uniqueKeysWithValues: bySlug.map { (builtinID(slug: $0.key), $0.value) })

    private static let doubleProgression = (
        en: "Keep the weight until every set reaches the top of the range, then add the smallest step and start again at the bottom.",
        zh: "重量不变，直到每组都做到区间上限；然后加最小一档，从区间下限重新开始。"
    )

    private static func guide(_ goal: Goal, who: (String, String), progress: (String, String)) -> ProgramGuide {
        ProgramGuide(goal: goal, whoEn: who.0, whoZh: who.1, progressEn: progress.0, progressZh: progress.1)
    }

    private static func doubleProgression(then en: String = "", _ zh: String = "") -> (String, String) {
        (
            en.isEmpty ? doubleProgression.en : "\(doubleProgression.en) \(en)",
            zh.isEmpty ? doubleProgression.zh : "\(doubleProgression.zh)\(zh)"
        )
    }

    static let bySlug: [String: ProgramGuide] = [
        // Beginner
        "beginner_full_body": guide(.strength,
            who: ("Learn the main barbell lifts and add weight almost every session.",
                  "学会杠铃基本动作，几乎每次训练都加重。"),
            progress: ("Finish every set of 5, then add 2.5 kg (5 lb) to upper-body lifts and 5 kg (10 lb) to squat and deadlift next time. Missed it twice at the same weight? Take 10% off and build back up. Other exercises: keep the weight until every set reaches the top of the range.",
                       "5 次的组全部做满，下次上肢加 2.5 kg、深蹲和硬拉加 5 kg；同一重量连续两次没做满，就减 10% 重新往上加。其他动作每组做到区间上限再加重。")),
        "machine_starter": guide(.allRound,
            who: ("First time in a gym? Guided machines instead of a crowded barbell rack.",
                  "第一次进健身房？用固定器械，不用去挤杠铃架。"),
            progress: ("When every set reaches the top of the range, move the pin up one step and start again at the bottom.",
                       "每组都做到区间上限后，器械加一格，从区间下限重新开始。")),
        "home_dumbbells": guide(.allRound,
            who: ("Train at home with a pair of adjustable dumbbells and a bench.",
                  "在家用一对可调哑铃和一张凳子训练。"),
            progress: ("Dumbbell jumps are big, so reach the top of the range on every set before moving up a pair.",
                       "哑铃跨度大，先把每组都做到区间上限，再换下一对。")),
        "two_day_full_body": guide(.quick,
            who: ("Only two sessions a week? Every muscle still gets trained twice.",
                  "每周只能练两次？每块肌肉依然能练到两次。"),
            progress: doubleProgression()),
        "upper_lower_starter": guide(.muscle,
            who: ("Four shorter sessions a week, upper and lower body on separate days.",
                  "每周四次、每次时间更短，上肢和下肢分开练。"),
            progress: doubleProgression()),
        // Intermediate
        "upper_lower": guide(.strengthAndMuscle,
            who: ("One heavy day and one higher-rep day for each half of the body.",
                  "上肢和下肢各有一个大重量日和一个高次数日。"),
            progress: doubleProgression(then: "On heavy days the step is 2.5–5 kg (5–10 lb).", "大重量日每次加 2.5–5 kg。")),
        "heavy_light_volume": guide(.strength,
            who: ("Adding weight every session has stalled, and you still want three days a week.",
                  "每次加重已经停滞，但仍想每周练三天。"),
            progress: ("Finish all 5 × 5 on the volume day, then add 2.5 kg (5 lb) next week. Heavy and light days: keep the weight until every set reaches the top of the range.",
                       "容量日 5×5 全部完成，下周加 2.5 kg；重日和轻日每组做到区间上限再加重。")),
        "strength_upper_lower": guide(.strength,
            who: ("Squat, bench, deadlift and press, each day split into heavy, medium and light work.",
                  "深蹲、卧推、硬拉、推举，每天按重、中、轻三层安排。"),
            progress: ("Add a small step to the 5 × 3 lift each time you finish it. Everything else: keep the weight until every set reaches the top of the range.",
                       "5×3 主项每次做完就加一小档；其他动作每组做到区间上限再加重。")),
        "upper_lower_ppl": guide(.muscle,
            who: ("Five days a week, built mainly to grow muscle.",
                  "每周五天，以增肌为主。"),
            progress: doubleProgression()),
        "superset_full_body": guide(.quick,
            who: ("Short on time: pairs of exercises back to back, done in about 45 minutes.",
                  "时间紧：两个动作一组交替做，约 45 分钟练完。"),
            progress: doubleProgression()),
        // Advanced
        "push_pull_legs": guide(.muscle,
            who: ("Six days a week and high weekly volume, with a heavy and a lighter version of each day.",
                  "每周六天、训练量高，每个部位有一重一轻两个版本。"),
            progress: doubleProgression(then: "Every 6–8 weeks, take a lighter week with half the sets.", "每 6–8 周安排一周减量，组数减半。")),
        "powerbuilding": guide(.strengthAndMuscle,
            who: ("Keep pushing your heavy lifts while you build size.",
                  "增肌的同时继续冲击大重量。"),
            progress: ("Power days: add 2.5–5 kg (5–10 lb) once every set reaches 5 reps. Other days: keep the weight until every set reaches the top of the range.",
                       "力量日每组都做到 5 次就加 2.5–5 kg；其他日每组做到区间上限再加重。")),
        "strength_block_build": guide(.strength,
            who: ("Four to six weeks of volume on squat, bench and deadlift before a max test or meet.",
                  "测极限或比赛前，用 4–6 周为深蹲、卧推、硬拉积累训练量。"),
            progress: ("Once every set reaches the top of the range, add 2.5 kg (5 lb) to bench and 5 kg (10 lb) to squat and deadlift. After 4–6 weeks, move on to block 2.",
                       "每组做到区间上限后，卧推加 2.5 kg，深蹲和硬拉加 5 kg。4–6 周后进入周期 2。")),
        "strength_block_peak": guide(.strength,
            who: ("Three heavy weeks after block 1, then a light week and a new max.",
                  "周期 1 之后练三周大重量，再减量一周，然后测新的极限。"),
            progress: ("Each week, add 2.5–5 kg (5–10 lb) to the main lifts while staying in the rep range: fewer sets, heavier weight.",
                       "每周主项加 2.5–5 kg，同时保持在次数区间内：组数少，重量大。")),
        "upper_body_focus": guide(.muscle,
            who: ("Chest, back, shoulders or arms lagging? Extra upper-body work, legs on maintenance.",
                  "胸、背、肩或手臂落后？加练上肢，腿部保持即可。"),
            progress: doubleProgression(then: "Run it for 6–8 weeks, then go back to a balanced program.", "练 6–8 周后换回均衡的计划。")),
    ]
}
