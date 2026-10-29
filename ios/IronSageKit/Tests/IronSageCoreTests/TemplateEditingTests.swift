import Foundation
import Testing

@testable import IronSageCore

struct TemplateEditingTests {
    let squat = UUID()
    let curl = UUID()

    var program: Template {
        Template(
            nameEn: "Upper / lower",
            nameZh: "上下肢分化",
            level: .intermediate,
            daysPerWeek: 4,
            days: [
                TemplateDay(name: "Lower A", nameZh: "下肢 A", exercises: [
                    TemplateExercise(exerciseId: squat, restSeconds: 180, sets: [
                        TemplateSet(setType: .warmup, repMin: 5, repMax: 5),
                        TemplateSet(repMin: 5, repMax: 8, targetRir: 2),
                        TemplateSet(repMin: 5, repMax: 8, targetRir: 2),
                    ]),
                ]),
            ],
            isCustom: false
        )
    }

    @Test func aCopyHasNewIdsAndTheNamesShown() {
        let copy = program.copy(named: "My upper / lower", chinese: true)

        #expect(copy.isCustom)
        #expect(copy.id != program.id)
        #expect(copy.nameEn == "My upper / lower")
        #expect(copy.nameZh == nil)
        #expect(copy.days[0].name == "下肢 A")
        #expect(copy.days[0].nameZh == nil)
        #expect(copy.days[0].id != program.days[0].id)
        #expect(copy.days[0].exercises[0].id != program.days[0].exercises[0].id)
        #expect(copy.days[0].exercises[0].exerciseId == squat)
        #expect(copy.days[0].exercises[0].restSeconds == 180)
        #expect(Set(copy.days[0].exercises[0].sets.map(\.id)).isDisjoint(with: program.days[0].exercises[0].sets.map(\.id)))
        #expect(copy.days[0].exercises[0].sets.map(\.repMax) == [5, 8, 8])
    }

    @Test func aTemplateNeedsNamesAndAnExerciseEachDay() {
        var template = Template.new(dayName: "Day 1")
        #expect(template.problem == .noName)
        template.nameEn = "  Mine "
        #expect(template.problem == .dayWithoutExercises)
        template.days[0].exercises = [.standard(squat)]
        template.days[0].name = " "
        #expect(template.problem == .dayWithoutName)
        template.days[0].name = "Legs"
        #expect(template.problem == nil)

        template.days.append(TemplateDay(name: " Arms ", exercises: [.standard(curl)]))
        let tidied = template.tidied()
        #expect(tidied.nameEn == "Mine")
        #expect(tidied.days.map(\.name) == ["Legs", "Arms"])
        #expect(tidied.daysPerWeek == 2)
    }

    @Test func aNewExerciseHasThreeSetsOfEightToTwelve() {
        let item = TemplateExercise.standard(curl)
        #expect(item.targets == TemplateTargets(sets: 3, repMin: 8, repMax: 12, rir: 2))
    }

    @Test func changingTargetsKeepsWarmupsAndExistingSets() {
        var item = program.days[0].exercises[0]
        let workingIDs = item.sets.dropFirst().map(\.id)
        #expect(item.targets == TemplateTargets(sets: 2, repMin: 5, repMax: 8, rir: 2))

        item.targets = TemplateTargets(sets: 3, repMin: 3, repMax: 5, rir: 1)

        #expect(item.sets.map(\.setType) == [.warmup, .working, .working, .working])
        #expect(item.sets[0].repMin == 5)
        #expect(Array(item.sets[1...2].map(\.id)) == workingIDs)
        #expect(item.sets.dropFirst().allSatisfy { $0.repMin == 3 && $0.repMax == 5 && $0.targetRir == 1 })

        item.targets.sets = 1
        #expect(item.sets.count == 2)
        item.targets.sets = 0
        #expect(item.targets.sets == 1)
    }

    @Test func aReversedRepRangeIsPutInOrder() {
        var item = TemplateExercise.standard(curl)
        item.targets.repMin = 15
        #expect(item.targets.repMin == 12)
        #expect(item.targets.repMax == 15)
    }
}
