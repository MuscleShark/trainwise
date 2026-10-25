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
