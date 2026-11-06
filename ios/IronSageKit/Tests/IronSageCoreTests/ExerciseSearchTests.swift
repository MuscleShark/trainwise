import Foundation
import Testing

@testable import IronSageCore

private func exercise(_ en: String, _ zh: String, aliases: [String] = [], equipment: Equipment = .barbell) -> Exercise {
    Exercise(nameEn: en, nameZh: zh, equipment: equipment, loadType: .total, primaryMuscles: [.chest], aliases: aliases, isCustom: false)
}

private let catalog = [
    exercise("Barbell bench press", "杠铃卧推", aliases: ["bench", "BP", "卧推"]),
    exercise("Incline barbell bench press", "上斜杠铃卧推", aliases: ["incline bench"]),
    exercise("Dumbbell bench press", "哑铃卧推", aliases: ["DB bench"], equipment: .dumbbell),
    exercise("Romanian deadlift", "罗马尼亚硬拉", aliases: ["RDL", "罗马硬拉"]),
    exercise("Deadlift", "硬拉", aliases: ["DL"]),
    exercise("Back squat", "杠铃深蹲", aliases: ["squat", "深蹲"]),
    exercise("Overhead press", "站姿杠铃推举", aliases: ["OHP", "推举"]),
]

private func names(_ query: String, chinese: Bool = false) -> [String] {
    ExerciseSearch(exercises: catalog, chinese: chinese).search(query).map { $0.exercise.name(chinese: chinese) }
}

@Test func emptyQueryListsEverythingByName() {
    #expect(names("").first == "Back squat")
    #expect(names("  ").count == catalog.count)
}

@Test func exactAndPrefixMatchesComeFirst() {
    #expect(names("deadlift").first == "Deadlift")
    #expect(names("bench").first == "Barbell bench press")
    #expect(names("incl").first == "Incline barbell bench press")
}

@Test func aliasesMatchAndAreShown() {
    let results = ExerciseSearch(exercises: catalog, chinese: false).search("rdl")
    #expect(results.first?.exercise.nameEn == "Romanian deadlift")
    #expect(results.first?.matched == "RDL")
    #expect(names("ohp").first == "Overhead press")
}

@Test func chineseNamesMatchInEitherLanguage() {
    #expect(names("卧推", chinese: true).first == "杠铃卧推")
    #expect(names("硬拉", chinese: true).first == "硬拉")
    // English UI, Chinese query: shows the English name and what matched.
    let result = ExerciseSearch(exercises: catalog, chinese: false).search("深蹲").first
    #expect(result?.exercise.nameEn == "Back squat")
    #expect(result?.matched == "深蹲")
}

@Test func pinyinAndItsInitialsMatch() {
    #expect(names("wotui", chinese: true).first == "杠铃卧推")
    #expect(names("shendun", chinese: true).first == "杠铃深蹲")
    #expect(names("glwt", chinese: true).first == "杠铃卧推")
    #expect(names("yl", chinese: true).first == "硬拉")
}

@Test func typosStillFindTheExercise() {
    #expect(names("benhc").first == "Barbell bench press")
    #expect(names("deadlfit").first == "Deadlift")
    #expect(names("romanain").first == "Romanian deadlift")
}

@Test func severalWordsMustAllMatch() {
    #expect(names("db bench").first == "Dumbbell bench press")
    #expect(names("incline press").first == "Incline barbell bench press")
}

@Test func unrelatedQueriesFindNothing() {
    #expect(names("zzzz").isEmpty)
    #expect(names("qz").isEmpty)
    // One letter only matches the start of a word.
    #expect(names("e").isEmpty)
}

@Test func editDistanceCountsASwapAsOneTypo() {
    #expect(ExerciseSearch.editDistance("benhc", "bench") == 1)
    #expect(ExerciseSearch.editDistance("squat", "squats") == 1)
    #expect(ExerciseSearch.editDistance("press", "bench") > 2)
}

// MARK: Equipment and muscles

private let gym = [
    Exercise(nameEn: "Dumbbell bench press", nameZh: "哑铃卧推", equipment: .dumbbell, loadType: .perSide, primaryMuscles: [.chest], secondaryMuscles: [.triceps], isCustom: false),
    Exercise(nameEn: "Dumbbell curl", nameZh: "哑铃弯举", equipment: .dumbbell, loadType: .perSide, primaryMuscles: [.biceps], isCustom: false),
    Exercise(nameEn: "Cable fly", nameZh: "绳索夹胸", equipment: .cable, loadType: .total, primaryMuscles: [.chest], isCustom: false),
    Exercise(nameEn: "Triceps pushdown", nameZh: "绳索下压", equipment: .cable, loadType: .total, primaryMuscles: [.triceps], isCustom: false),
    Exercise(nameEn: "Lat pulldown", nameZh: "高位下拉", equipment: .cable, loadType: .total, primaryMuscles: [.lats], secondaryMuscles: [.biceps], isCustom: false),
    Exercise(nameEn: "Back squat", nameZh: "杠铃深蹲", equipment: .barbell, loadType: .total, primaryMuscles: [.quads, .glutes], secondaryMuscles: [.lowerBack], isCustom: false),
    Exercise(nameEn: "Leg press", nameZh: "腿举", equipment: .machine, loadType: .total, primaryMuscles: [.quads], isCustom: false),
]

private func found(_ query: String, chinese: Bool = false) -> [String] {
    ExerciseSearch(exercises: gym, chinese: chinese).search(query).map(\.exercise.nameEn)
}

@Test func equipmentFindsEveryExerciseThatUsesIt() {
    #expect(Set(found("dumbbell")) == ["Dumbbell bench press", "Dumbbell curl"])
    #expect(Set(found("绳索", chinese: true)) == ["Cable fly", "Triceps pushdown", "Lat pulldown"])
    // Still being typed, and in pinyin.
    #expect(Set(found("dumbb")) == ["Dumbbell bench press", "Dumbbell curl"])
    #expect(Set(found("yaling", chinese: true)) == ["Dumbbell bench press", "Dumbbell curl"])
}

@Test func aMuscleFindsItsExercisesMainOnesFirst() {
    #expect(found("chest") == ["Cable fly", "Dumbbell bench press"])
    #expect(Set(found("胸", chinese: true)) == ["Cable fly", "Dumbbell bench press"])
    // Triceps help on the bench press, so it comes after the pushdown.
    #expect(found("triceps") == ["Triceps pushdown", "Dumbbell bench press"])
    // A group: the back is the upper back, lats and lower back.
    #expect(found("背", chinese: true).first == "Lat pulldown")
    #expect(Set(found("legs")) == ["Back squat", "Leg press"])
}

@Test func equipmentAndMuscleTogetherNarrowIt() {
    #expect(found("dumbbell chest") == ["Dumbbell bench press"])
    #expect(found("哑铃胸", chinese: true) == ["Dumbbell bench press"])
    #expect(found("cable triceps") == ["Triceps pushdown"])
    // What's left matches the name.
    #expect(found("cable pull") == ["Lat pulldown"])
}

@Test func aNameMatchStillComesBeforeAnEquipmentOrMuscleMatch() {
    #expect(found("back squat").first == "Back squat")
    #expect(found("腿举", chinese: true).first == "Leg press")
    #expect(found("dumbbell curl").first == "Dumbbell curl")
}
