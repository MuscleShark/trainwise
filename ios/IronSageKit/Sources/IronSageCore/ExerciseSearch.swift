import Foundation

/// Finds exercises as people type them: in English or Chinese, by alias ("RDL", "卧推"),
/// by pinyin ("wotui", or initials "wt"), with a typo or two ("benhc"), and by
/// equipment or muscle ("dumbbell", "哑铃", "chest", "背", "哑铃胸", "cable triceps").
/// An exercise whose name matches comes before one found by its equipment or muscle.
///
/// Results show the name in the app's language; when something else matched (an alias
/// or the other language's name), `matched` says what, so "RDL" shows
/// "Romanian deadlift" with "RDL" next to it.
public struct ExerciseSearch: Sendable {
    public struct Result: Identifiable, Hashable, Sendable {
        public let exercise: Exercise
        /// The alias or other-language name that matched; nil when the shown name did.
        public let matched: String?
        public var id: UUID { exercise.id }

        public init(exercise: Exercise, matched: String?) {
            self.exercise = exercise
            self.matched = matched
        }
    }

    private struct Candidate: Sendable {
        enum Kind: Int, Sendable {
            // Lower is better when scores tie.
            case name, otherName, alias, pinyin
        }

        let kind: Kind
        let original: String
        let compact: String
        let words: [String]
        let initials: String?
    }

    private struct Entry: Sendable {
        let exercise: Exercise
        let candidates: [Candidate]
    }

    private let entries: [Entry]
    private let chinese: Bool

    public init(exercises: [Exercise], chinese: Bool) {
        self.chinese = chinese
        entries = exercises.map { exercise in
            var candidates: [Candidate] = []
            let shown = exercise.name(chinese: chinese)
            candidates.append(Self.candidate(.name, shown))
            let other = chinese ? exercise.nameEn : exercise.nameZh
            if let other, other != shown {
                candidates.append(Self.candidate(.otherName, other))
            }
            for alias in exercise.aliases {
                candidates.append(Self.candidate(.alias, alias))
            }
            for chineseText in [exercise.nameZh].compactMap(\.self) + exercise.aliases where Self.hasHan(chineseText) {
                let syllables = Self.pinyin(chineseText)
                if !syllables.isEmpty {
                    candidates.append(Candidate(
                        kind: .pinyin,
                        original: chineseText,
                        compact: syllables.joined(),
                        words: syllables,
                        initials: String(syllables.compactMap(\.first))
                    ))
                }
            }
            return Entry(exercise: exercise, candidates: candidates)
        }
    }

    /// Best matches first. An empty query returns everything by name.
    public func search(_ query: String, limit: Int = 60) -> [Result] {
        let queryWords = Self.words(query)
        let compactQuery = queryWords.joined()
        if compactQuery.isEmpty {
            return entries
                .map { Result(exercise: $0.exercise, matched: nil) }
                .sorted { $0.exercise.name(chinese: chinese).localizedStandardCompare($1.exercise.name(chinese: chinese)) == .orderedAscending }
        }

        let filter = Self.attributes(in: queryWords)
        let restWords = filter.rest
        let restCompact = restWords.joined()
        var scored: [(result: Result, score: Int, kind: Int, length: Int)] = []
        for entry in entries {
            var matched: String?
            var score = 0
            var kind = Candidate.Kind.name.rawValue
            if let best = Self.best(compactQuery, queryWords, entry) {
                let showsMatch = best.candidate.kind == .otherName || best.candidate.kind == .alias
                    || (best.candidate.kind == .pinyin && best.candidate.original != entry.exercise.name(chinese: chinese))
                matched = showsMatch ? best.candidate.original : nil
                score = best.score
                kind = best.candidate.kind.rawValue
            }
            // By equipment or muscle, with what's left of the query matched to the name.
            if !filter.attributes.isEmpty, let fit = Self.fit(entry.exercise, filter.attributes) {
                var byAttribute = fit
                if !restCompact.isEmpty {
                    guard let rest = Self.best(restCompact, restWords, entry) else { continue }
                    byAttribute += min(rest.score, 90) / 10
                }
                if byAttribute > score {
                    score = byAttribute
                    matched = nil
                }
            }
            guard score > 0 else { continue }
            scored.append((
                Result(exercise: entry.exercise, matched: matched),
                score,
                kind,
                entry.exercise.name(chinese: chinese).count
            ))
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
                return lhs.length < rhs.length
            }
            .prefix(limit)
            .map(\.result)
    }

    // MARK: Scoring

    private static func best(_ query: String, _ queryWords: [String], _ entry: Entry) -> (score: Int, candidate: Candidate)? {
        var best: (score: Int, candidate: Candidate)?
        for candidate in entry.candidates {
            let score = score(query, queryWords, candidate)
            if score > 0, score > best?.score ?? 0
                || (score == best?.score && candidate.kind.rawValue < best!.candidate.kind.rawValue) {
                best = (score, candidate)
            }
        }
        return best
    }

    private static func score(_ query: String, _ queryWords: [String], _ candidate: Candidate) -> Int {
        let text = candidate.compact
        if text == query { return 100 }
        if text.hasPrefix(query) { return 90 }
        if queryWords.count == 1, candidate.words.contains(where: { $0.hasPrefix(query) }) { return 80 }
        if let initials = candidate.initials, query.count >= 2, initials.hasPrefix(query) { return 76 }
        // Inside a word only from two letters on; one letter matches too much. One
        // Chinese character is a word of its own.
        if query.count >= 2 || hasHan(query), text.contains(query) { return 70 }
        if queryWords.count > 1, queryWords.allSatisfy({ word in
            candidate.words.contains { $0.hasPrefix(word) || isTypo(of: word, in: $0) }
        }) {
            return 65
        }
        // Typos: compare with whole words, and with the start of the name.
        if query.count >= 4 {
            if candidate.words.contains(where: { isTypo(of: query, in: $0) }) { return 50 }
            if isTypo(of: query, in: String(text.prefix(query.count))) { return 45 }
        }
        return 0
    }

    /// True when `typed` is within a small edit distance of `word` (or of its start).
    private static func isTypo(of typed: String, in word: String) -> Bool {
        guard typed.count >= 4, !hasHan(typed) else { return false }
        let allowed = typed.count >= 8 ? 2 : 1
        let target = word.count > typed.count + allowed ? String(word.prefix(typed.count)) : word
        return editDistance(typed, target, limit: allowed) <= allowed
    }

    /// Damerau-Levenshtein (optimal string alignment) distance, so a swapped pair of
    /// letters ("benhc") counts as one typo.
    static func editDistance(_ a: String, _ b: String, limit: Int = .max) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previousPrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = min(current[j], previousPrevious[j - 2] + 1)
                }
            }
            (previousPrevious, previous, current) = (previous, current, previousPrevious)
        }
        return previous[b.count]
    }

    // MARK: Text

    private static func candidate(_ kind: Candidate.Kind, _ text: String) -> Candidate {
        let words = words(text)
        return Candidate(kind: kind, original: text, compact: words.joined(), words: words, initials: nil)
    }

    /// Lowercased words without accents or punctuation. Chinese stays one word per run
    /// of characters, since it has no spaces.
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// "杠铃卧推" → ["gang", "ling", "wo", "tui"].
    static func pinyin(_ text: String) -> [String] {
        let latin = text.applyingTransform(.mandarinToLatin, reverse: false) ?? ""
        return words(latin).filter { !hasHan($0) }
    }

    private static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }
}

// MARK: Equipment and muscles

extension ExerciseSearch {
    /// Something a query can name besides the exercise: its equipment, or a muscle or
    /// group of muscles ("back" is the upper back, lats and lower back).
    enum Attribute: Hashable, Sendable {
        case equipment(Equipment)
        case muscles(Set<Muscle>)
    }

    /// Words for each attribute, in English and Chinese. Their pinyin is added too.
    private static let terms: [(words: [String], attribute: Attribute)] = {
        let equipment: [(Equipment, [String])] = [
            (.barbell, ["barbell", "barbells", "bb", "杠铃"]),
            (.dumbbell, ["dumbbell", "dumbbells", "db", "哑铃"]),
            (.machine, ["machine", "machines", "器械", "固定器械"]),
            (.cable, ["cable", "cables", "绳索", "龙门架", "拉力器"]),
            (.smith, ["smith", "smith machine", "史密斯", "史密斯机"]),
            (.bodyweight, ["bodyweight", "body weight", "自重", "徒手"]),
            (.kettlebell, ["kettlebell", "kettlebells", "kb", "壶铃"]),
            (.band, ["band", "bands", "resistance band", "弹力带"]),
        ]
        let muscles: [(Set<Muscle>, [String])] = [
            ([.chest], ["chest", "pec", "pecs", "胸", "胸部", "胸肌"]),
            ([.upperBack], ["upper back", "上背"]),
            ([.lats], ["lat", "lats", "背阔肌", "背阔"]),
            ([.traps], ["trap", "traps", "斜方肌", "斜方"]),
            ([.frontDelts], ["front delt", "front delts", "前束", "前三角"]),
            ([.sideDelts], ["side delt", "side delts", "lateral delt", "中束", "中三角"]),
            ([.rearDelts], ["rear delt", "rear delts", "后束", "后三角"]),
            ([.biceps], ["bicep", "biceps", "二头", "肱二头肌"]),
            ([.triceps], ["tricep", "triceps", "三头", "肱三头肌"]),
            ([.forearms], ["forearm", "forearms", "前臂", "小臂"]),
            ([.abs], ["abs", "ab", "abdominals", "腹肌", "腹"]),
            ([.obliques], ["oblique", "obliques", "腹斜肌"]),
            ([.lowerBack], ["lower back", "下背", "腰"]),
            ([.glutes], ["glute", "glutes", "butt", "臀", "臀部", "臀肌"]),
            ([.quads], ["quad", "quads", "quadriceps", "股四头肌", "股四", "大腿前侧"]),
            ([.hamstrings], ["hamstring", "hamstrings", "hammies", "腘绳肌", "大腿后侧"]),
            ([.adductors], ["adductor", "adductors", "内收肌", "内收"]),
            ([.abductors], ["abductor", "abductors", "外展肌", "外展"]),
            ([.calves], ["calf", "calves", "小腿"]),
            ([.upperBack, .lats, .lowerBack], ["back", "背", "背部"]),
            ([.frontDelts, .sideDelts, .rearDelts], ["shoulder", "shoulders", "delt", "delts", "肩", "肩部", "三角肌"]),
            ([.biceps, .triceps, .forearms], ["arm", "arms", "手臂", "胳膊"]),
            ([.quads, .hamstrings, .glutes, .adductors, .abductors, .calves], ["leg", "legs", "腿", "腿部", "下肢"]),
            ([.abs, .obliques], ["core", "核心"]),
        ]
        var all = equipment.map { (words: $0.1, attribute: Attribute.equipment($0.0)) }
            + muscles.map { (words: $0.1, attribute: Attribute.muscles($0.0)) }
        for index in all.indices {
            // "yaling", "xiong": the pinyin of each Chinese word, as one Latin word.
            let spelled = all[index].words.filter { Self.hasHan($0) }.map { Self.pinyin($0).joined() }.filter { $0.count >= 3 }
            all[index].words += spelled
        }
        return all
    }()

    /// Longest words first, so "upper back" wins over "back" and "史密斯机" over "史密斯".
    private static let orderedTerms: [(word: String, attribute: Attribute)] = terms
        .flatMap { term in term.words.map { (word: $0, attribute: term.attribute) } }
        .sorted { $0.word.count > $1.word.count }

    /// The equipment and muscles a query names, and the words left for the name. Chinese
    /// has no spaces, so "哑铃胸" names both; a Latin word that is still being typed
    /// ("dumbb", three letters or more) counts when it is the last one.
    static func attributes(in queryWords: [String]) -> (attributes: [Attribute], rest: [String]) {
        var rest = queryWords
        var found: [Attribute] = []
        for (term, attribute) in orderedTerms {
            if hasHan(term) {
                for index in rest.indices where rest[index].contains(term) {
                    rest[index] = rest[index].replacingOccurrences(of: term, with: " ")
                    found.append(attribute)
                }
                rest = rest.flatMap { $0.split(separator: " ").map(String.init) }
                continue
            }
            let termWords = words(term)
            guard !termWords.isEmpty, rest.count >= termWords.count else { continue }
            var start = 0
            while start + termWords.count <= rest.count {
                let slice = Array(rest[start..<start + termWords.count])
                let isLast = start + termWords.count == rest.count
                let matches = zip(slice, termWords).enumerated().allSatisfy { offset, pair in
                    pair.0 == pair.1
                        || (isLast && offset == termWords.count - 1 && pair.0.count >= 3 && pair.1.hasPrefix(pair.0))
                }
                if matches {
                    rest.removeSubrange(start..<start + termWords.count)
                    found.append(attribute)
                } else {
                    start += 1
                }
            }
        }
        // One attribute per kind of thing named twice ("哑铃 dumbbell") is enough.
        var unique: [Attribute] = []
        for attribute in found where !unique.contains(attribute) {
            unique.append(attribute)
        }
        return (unique, rest)
    }

    /// How well an exercise fits every attribute: 60 when each is its equipment or a main
    /// muscle, 52 when a muscle only helps. Nil when one doesn't fit.
    static func fit(_ exercise: Exercise, _ attributes: [Attribute]) -> Int? {
        var score = 60
        for attribute in attributes {
            switch attribute {
            case .equipment(let equipment):
                guard exercise.equipment == equipment else { return nil }
            case .muscles(let muscles):
                if !muscles.isDisjoint(with: exercise.primaryMuscles) { continue }
                guard !muscles.isDisjoint(with: exercise.secondaryMuscles) else { return nil }
                score = min(score, 52)
            }
        }
        return score
    }
}
