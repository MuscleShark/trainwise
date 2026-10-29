#if DEBUG
import Foundation
import IronSageCore
import IronSageStore

/// Sample data for `-demo` launches (screenshots and trying screens without an account).
@MainActor
enum DemoData {
    static func fill(_ store: LocalStore, coach: CoachService) {
        let bench = exercise("barbell_bench_press", "Barbell bench press", "杠铃卧推", .barbell, .total, [.chest], [.frontDelts, .triceps], ["bench", "卧推"])
        let squat = exercise("back_squat", "Back squat", "杠铃深蹲", .barbell, .total, [.quads, .glutes], [.adductors, .lowerBack], ["squat", "深蹲"])
        let rdl = exercise("romanian_deadlift", "Romanian deadlift", "罗马尼亚硬拉", .barbell, .total, [.hamstrings, .glutes], [.lowerBack], ["RDL", "罗马硬拉"])
        let row = exercise("barbell_row", "Barbell row", "杠铃划船", .barbell, .total, [.upperBack, .lats], [.biceps, .rearDelts], ["bent-over row"])
        let press = exercise("overhead_press", "Overhead press", "站姿杠铃推举", .barbell, .total, [.frontDelts], [.triceps, .sideDelts], ["OHP", "推举"])
        let pulldown = exercise("lat_pulldown", "Lat pulldown", "高位下拉", .cable, .total, [.lats], [.biceps, .upperBack], ["pulldown", "下拉"])
        let curl = exercise("dumbbell_curl", "Dumbbell curl", "哑铃弯举", .dumbbell, .perSide, [.biceps], [.forearms], [])
        let raise = exercise("lateral_raise", "Dumbbell lateral raise", "哑铃侧平举", .dumbbell, .perSide, [.sideDelts], [.traps], ["侧平举"])
        store.replaceBuiltInExercises([bench, squat, rdl, row, press, pulldown, curl, raise])
        let ppl = Template(
            nameEn: "Push / pull / legs", nameZh: "推拉腿", level: .intermediate, daysPerWeek: 6,
            days: [
                day("Push", "推", [(bench, 4, 5, 8, 180), (press, 3, 6, 10, 180), (raise, 3, 12, 20, 90)]),
                day("Pull", "拉", [(row, 4, 6, 10, 180), (pulldown, 3, 8, 12, 180), (curl, 3, 10, 12, 90)]),
                day("Legs", "腿", [(squat, 4, 5, 8, 180), (rdl, 3, 8, 10, 180)]),
            ],
            isCustom: false
        )
        store.replaceBuiltInTemplates([ppl])

        // The workouts follow the template, so Today suggests the next day.
        func workout(_ day: String, daysAgo: Int, _ items: [(Exercise, Int, [(Double, Int)])]) -> Workout {
            Self.workout("\(ppl.nameEn) · \(day)", templateID: ppl.id, daysAgo: daysAgo, items)
        }
        store.save(workout("Push", daysAgo: 4, [(bench, 180, [(60, 8), (60, 8), (60, 7)]), (press, 150, [(40, 8), (40, 7)]), (raise, 90, [(8, 12), (8, 12)])]))
        store.save(workout("Legs", daysAgo: 2, [(squat, 180, [(100, 5), (100, 5), (100, 5)]), (rdl, 150, [(80, 10), (80, 10)])]))
        store.save(workout("Pull", daysAgo: 1, [(row, 150, [(70, 8), (70, 8)]), (pulldown, 120, [(55, 10), (55, 10)]), (curl, 90, [(12, 10), (12, 9)])]))

        // Six earlier weeks, a little lighter each week back.
        for week in 1...6 {
            let back = Double(week) * 2.5
            store.save(workout("Push", daysAgo: 4 + 7 * week, [(bench, 180, [(60 - back, 8), (60 - back, 8), (60 - back, 6)]), (press, 150, [(40 - back / 2, 8), (40 - back / 2, 6)])]))
            store.save(workout("Legs", daysAgo: 2 + 7 * week, [(squat, 180, [(100 - back * 2, 5), (100 - back * 2, 5), (100 - back * 2, 5)]), (rdl, 150, [(80 - back, 8), (80 - back, 8)])]))
        }
        fillHealth(store)
        fillCoach(store, coach: coach)
    }

    /// The AI coach turned on, with an answer for the day due next (Legs).
    private static func fillCoach(_ store: LocalStore, coach: CoachService) {
        coach.turnOn()
        guard let day = store.upNext?.day else { return }
        let today = HealthDays.key(.now)
        let context = store.nextSessionContext()
        guard let request = Coach.request(
            for: day, exercises: store.exercises, context: context,
            readiness: ReadinessComparison.compare(store.readiness, on: today),
            profile: store.profile, chinese: AppLanguage.isChinese
        ) else { return }
        let chinese = AppLanguage.isChinese
        let reasons = [
            chinese ? "上次每组都是 5 次，今天同样重量争取每组 6 次。" : "You got 5 reps on every set last time, so aim for 6 at the same weight.",
            chinese ? "上次每组都做到了 10 次，今天加一档重量，从 8 次开始。" : "You reached 10 reps on every set, so one step heavier today, starting at 8.",
        ]
        let advice = CoachAdvice(
            summary: chinese ? "睡眠和平时差不多，按计划练：深蹲加次数，硬拉加重量。" : "You slept about as usual, so follow the plan: more squat reps, more deadlift weight.",
            exercises: request.exercises.enumerated().map { index, plan in
                .init(exerciseId: plan.exerciseId, action: .follow, reason: reasons[min(index, reasons.count - 1)], sets: plan.plannedSets)
            },
            model: "anthropic:claude-sonnet-5-5"
        )
        let key = Coach.planKey(day: day, lastWorkout: store.finishedWorkouts.first, readiness: store.readiness[today], request: request)
        store.save(Recommendation(forDate: today, status: .ready, output: advice, request: request, planKey: key, requestedAt: .now))

        guard let week = Coach.lastWeekStart() else { return }
        let summary = chinese
            ? "上周你练了 3 次。胸部 9.5 组、股四头肌 8 组，都低于 10 到 20 组的参考范围。深蹲做到了 100 公斤 × 5 次，是新纪录。睡眠平均 7 小时，和平时差不多。"
            : "You trained 3 times last week. Chest got 9.5 sets and quads 8, both under the 10 to 20 reference band. Your squat hit a new best of 100 kg × 5. Sleep averaged 7 h, about as usual."
        let suggestions = chinese
            ? ["下周给胸部和腿各加 2 组。", "卧推最近进步慢，可以试试 6 到 10 次的次数范围。"]
            : ["Add 2 sets each for chest and legs next week.", "Bench press progress has slowed; try a 6 to 10 rep range."]
        store.save(WeeklySummary(
            weekStart: week, status: .ready,
            output: .init(summary: summary, suggestions: suggestions, deload: false, model: "anthropic:claude-sonnet-5-5")
        ))
    }

    /// Five weeks of nights, morning weights and weekly body fat, with a little day-to-day noise.
    private static func fillHealth(_ store: LocalStore) {
        let calendar = Calendar.current
        for daysAgo in 0..<35 {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
            let wobble = Double((daysAgo * 37) % 11 - 5)  // -5...5, repeatable
            let sleep = 420 + Int(wobble * 6)
            store.save(Readiness(
                date: HealthDays.key(date, calendar: calendar),
                sleepMinutes: sleep,
                deepMinutes: sleep / 7,
                remMinutes: sleep / 5,
                coreMinutes: sleep - sleep / 7 - sleep / 5,
                awakeMinutes: 20,
                hrvSdnnMs: 52 + wobble * 1.5,
                restingHrBpm: 56 - wobble / 2
            ))
            if daysAgo % 3 == 0 {
                let morning = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: date)!
                store.save(BodyMeasurement(measuredAt: morning, value: 80 - Double(35 - daysAgo) * 0.04 + wobble * 0.1, source: .healthkit))
            }
            if daysAgo % 7 == 0 {
                let morning = calendar.date(bySettingHour: 7, minute: 31, second: 0, of: date)!
                store.save(BodyMeasurement(measuredAt: morning, kind: .bodyFat, value: 18 + Double(daysAgo) * 0.04 + wobble * 0.05, source: .healthkit))
            }
        }
    }

    /// A built-in exercise with the ID the API gives it, so its picture shows.
    private static func exercise(_ slug: String, _ en: String, _ zh: String, _ equipment: Equipment, _ load: LoadType, _ primary: [Muscle], _ secondary: [Muscle], _ aliases: [String]) -> Exercise {
        Exercise(id: ExerciseVisuals.builtinID(slug: slug), nameEn: en, nameZh: zh, equipment: equipment, loadType: load, primaryMuscles: primary, secondaryMuscles: secondary, aliases: aliases, isCustom: false)
    }

    private static func day(_ en: String, _ zh: String, _ items: [(Exercise, Int, Int, Int, Int)]) -> TemplateDay {
        TemplateDay(name: en, nameZh: zh, exercises: items.map { exercise, sets, low, high, rest in
            TemplateExercise(
                exerciseId: exercise.id,
                restSeconds: rest,
                sets: (0..<sets).map { _ in TemplateSet(repMin: low, repMax: high, targetRir: rest > 90 ? 2 : 1) }
            )
        })
    }

    private static func workout(_ title: String, templateID: UUID?, daysAgo: Int, _ items: [(Exercise, Int, [(Double, Int)])]) -> Workout {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!.addingTimeInterval(-3600)
        return Workout(
            title: title,
            templateId: templateID,
            startedAt: start,
            endedAt: start.addingTimeInterval(65 * 60),
            exercises: items.map { exercise, rest, sets in
                WorkoutExercise(
                    exerciseId: exercise.id,
                    restSeconds: rest,
                    sets: sets.map { WorkoutSet(reps: $0.1, weightKg: $0.0, rir: 2, completedAt: start) }
                )
            }
        )
    }
}
#endif
