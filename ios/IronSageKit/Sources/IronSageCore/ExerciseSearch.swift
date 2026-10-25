import Foundation

/// Finds exercises as people type them: in English or Chinese, by alias ("RDL", "卧推"),
/// by pinyin ("wotui", or initials "wt"), and with a typo or two ("benhc").
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

        var scored: [(result: Result, score: Int, kind: Int, length: Int)] = []
        for entry in entries {
            var best: (score: Int, candidate: Candidate)?
            for candidate in entry.candidates {
                let score = Self.score(compactQuery, queryWords, candidate)
                if score > 0, score > best?.score ?? 0
                    || (score == best?.score && candidate.kind.rawValue < best!.candidate.kind.rawValue) {
                    best = (score, candidate)
                }
            }
            guard let best else { continue }
            let showsMatch = best.candidate.kind == .otherName || best.candidate.kind == .alias
                || (best.candidate.kind == .pinyin && best.candidate.original != entry.exercise.name(chinese: chinese))
            scored.append((
                Result(exercise: entry.exercise, matched: showsMatch ? best.candidate.original : nil),
                best.score,
                best.candidate.kind.rawValue,
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
