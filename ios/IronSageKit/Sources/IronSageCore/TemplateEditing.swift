import Foundation

/// Building and changing the user's own templates.
extension Template {
    /// The API's limits for a template.
    public static let maxDays = 7
    public static let maxExercisesPerDay = 30
    public static let maxNameLength = 120

    /// An empty template of the user's own with one day.
    public static func new(dayName: String) -> Template {
        Template(nameEn: "", daysPerWeek: 1, days: [TemplateDay(name: dayName)], isCustom: true)
    }

    /// The user's own copy, named `name`. Every day, exercise and set gets a new id (the
    /// server keys them by id across all templates), and days keep the names shown in the
    /// app's language, since the user's own days have one name only.
    public func copy(named name: String, chinese: Bool) -> Template {
        Template(
            nameEn: String(name.prefix(Self.maxNameLength)),
            level: level,
            daysPerWeek: daysPerWeek,
            notes: notes,
            days: days.map { day in
                TemplateDay(name: day.name(chinese: chinese), exercises: day.exercises.map { item in
                    TemplateExercise(
                        exerciseId: item.exerciseId,
                        restSeconds: item.restSeconds,
                        supersetGroup: item.supersetGroup,
                        sets: item.sets.map {
                            TemplateSet(setType: $0.setType, repMin: $0.repMin, repMax: $0.repMax, targetRir: $0.targetRir)
                        }
                    )
                })
            },
            isCustom: true
        )
    }

    /// What keeps the template from being saved, or nil when nothing does.
    public var problem: TemplateProblem? {
        if nameEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .noName }
        if days.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return .dayWithoutName }
        if days.contains(where: \.exercises.isEmpty) { return .dayWithoutExercises }
        return nil
    }

    /// Ready to save: names trimmed, and the days per week matching the days.
    public func tidied() -> Template {
        var template = self
        template.nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        template.nameZh = nil
        for index in template.days.indices {
            template.days[index].name = template.days[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        template.daysPerWeek = days.count
        return template
    }
}

public enum TemplateProblem: Hashable, Sendable {
    case noName, dayWithoutName, dayWithoutExercises
}

/// The target every working set of an exercise in a template shares, as the editor shows it.
public struct TemplateTargets: Hashable, Sendable {
    public var sets: Int
    public var repMin: Int?
    public var repMax: Int?
    public var rir: Int?

    public init(sets: Int, repMin: Int?, repMax: Int?, rir: Int?) {
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
        self.rir = rir
    }

    public static let maxSets = 20
}

extension TemplateExercise {
    /// A new exercise in a template: three working sets of 8–12 reps, two short of failure.
    public static func standard(_ exerciseId: UUID) -> TemplateExercise {
        TemplateExercise(
            exerciseId: exerciseId,
            sets: (0..<3).map { _ in TemplateSet(repMin: 8, repMax: 12, targetRir: 2) }
        )
    }

    /// The working sets' count and the first one's target. Setting it gives every working
    /// set that target; warm-up sets stay first and unchanged, and existing sets keep their
    /// ids and types (drop, failure).
    public var targets: TemplateTargets {
        get {
            let working = sets.filter { $0.setType != .warmup }
            return TemplateTargets(
                sets: working.count,
                repMin: working.first?.repMin,
                repMax: working.first?.repMax,
                rir: working.first?.targetRir
            )
        }
        set {
            let warmups = sets.filter { $0.setType == .warmup }
            let working = sets.filter { $0.setType != .warmup }
            let count = max(1, min(newValue.sets, TemplateTargets.maxSets - warmups.count))
            var repMin = newValue.repMin
            var repMax = newValue.repMax
            if let low = repMin, let high = repMax, low > high {
                (repMin, repMax) = (high, low)
            }
            sets = warmups + (0..<count).map { index in
                TemplateSet(
                    id: index < working.count ? working[index].id : UUID(),
                    setType: index < working.count ? working[index].setType : .working,
                    repMin: repMin,
                    repMax: repMax,
                    targetRir: newValue.rir
                )
            }
        }
    }
}
