#if DEBUG
import Foundation
import IronSageCore
import IronSageStore

/// Sample data for `-demo` launches (screenshots and trying screens without an account).
@MainActor
enum DemoData {
    static func fill(_ store: LocalStore) {
        let bench = exercise("Barbell bench press", "杠铃卧推", .barbell, .total, [.chest], [.frontDelts, .triceps], ["bench", "卧推"])
        let squat = exercise("Back squat", "杠铃深蹲", .barbell, .total, [.quads, .glutes], [.adductors, .lowerBack], ["squat", "深蹲"])
        let rdl = exercise("Romanian deadlift", "罗马尼亚硬拉", .barbell, .total, [.hamstrings, .glutes], [.lowerBack], ["RDL", "罗马硬拉"])
        let row = exercise("Barbell row", "杠铃划船", .barbell, .total, [.upperBack, .lats], [.biceps, .rearDelts], ["bent-over row"])
        let press = exercise("Overhead press", "站姿杠铃推举", .barbell, .total, [.frontDelts], [.triceps, .sideDelts], ["OHP", "推举"])
        let pulldown = exercise("Lat pulldown", "高位下拉", .cable, .total, [.lats], [.biceps, .upperBack], ["pulldown", "下拉"])
        let curl = exercise("Dumbbell curl", "哑铃弯举", .dumbbell, .perSide, [.biceps], [.forearms], [])
        let raise = exercise("Dumbbell lateral raise", "哑铃侧平举", .dumbbell, .perSide, [.sideDelts], [.traps], ["侧平举"])
        store.replaceBuiltInExercises([bench, squat, rdl, row, press, pulldown, curl, raise])
        store.replaceBuiltInTemplates([Template(
            nameEn: "Push / pull / legs", nameZh: "推拉腿", level: .intermediate, daysPerWeek: 6,
            days: [
                day("Push", "推", [(bench, 4, 5, 8, 180), (press, 3, 6, 10, 180), (raise, 3, 12, 20, 90)]),
                day("Pull", "拉", [(row, 4, 6, 10, 180), (pulldown, 3, 8, 12, 180), (curl, 3, 10, 12, 90)]),
                day("Legs", "腿", [(squat, 4, 5, 8, 180), (rdl, 3, 8, 10, 180)]),
            ],
            isCustom: false
        )])

        store.save(workout("Push", daysAgo: 4, [(bench, 180, [(60, 8), (60, 8), (60, 7)]), (press, 150, [(40, 8), (40, 7)]), (raise, 90, [(8, 12), (8, 12)])]))
        store.save(workout("Legs", daysAgo: 2, [(squat, 180, [(100, 5), (100, 5), (100, 5)]), (rdl, 150, [(80, 8), (80, 8)])]))
        store.save(workout("Pull", daysAgo: 1, [(row, 150, [(70, 8), (70, 8)]), (pulldown, 120, [(55, 10), (55, 10)]), (curl, 90, [(12, 10), (12, 9)])]))
    }

    private static func exercise(_ en: String, _ zh: String, _ equipment: Equipment, _ load: LoadType, _ primary: [Muscle], _ secondary: [Muscle], _ aliases: [String]) -> Exercise {
        Exercise(nameEn: en, nameZh: zh, equipment: equipment, loadType: load, primaryMuscles: primary, secondaryMuscles: secondary, aliases: aliases, isCustom: false)
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

    private static func workout(_ title: String, daysAgo: Int, _ items: [(Exercise, Int, [(Double, Int)])]) -> Workout {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!.addingTimeInterval(-3600)
        return Workout(
            title: title,
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
