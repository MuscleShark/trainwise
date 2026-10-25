import Foundation

// The app's own types for what it stores and shows. They mirror the API's schemas (the
// store converts with JSON, see IronSageStore/Wire.swift) but stay free of generated
// code, so views and logic can use them without the networking layer.

public enum Muscle: String, Codable, CaseIterable, Hashable, Sendable {
    case chest
    case upperBack = "upper_back"
    case lats, traps
    case frontDelts = "front_delts"
    case sideDelts = "side_delts"
    case rearDelts = "rear_delts"
    case biceps, triceps, forearms, abs, obliques
    case lowerBack = "lower_back"
    case glutes, quads, hamstrings, adductors, abductors, calves
}

public enum Equipment: String, Codable, CaseIterable, Hashable, Sendable {
    case barbell, dumbbell, machine, cable, smith, bodyweight, kettlebell, band, other
}

/// What the logged weight means.
public enum LoadType: String, Codable, CaseIterable, Hashable, Sendable {
    /// The whole load: a barbell with plates, a machine stack.
    case total
    /// One dumbbell, cable handle or lever arm.
    case perSide = "per_side"
    /// Weight added to the body, as on weighted pull-ups.
    case bodyweightPlus = "bodyweight_plus"
    /// Assistance: more weight is easier.
    case assisted
}

public enum SetType: String, Codable, CaseIterable, Hashable, Sendable {
    case warmup, working, drop, failure
}

public enum Level: String, Codable, CaseIterable, Hashable, Sendable {
    case beginner, intermediate, advanced
}

public enum UnitSystem: String, Codable, CaseIterable, Hashable, Sendable {
    case metric, imperial
}

public enum Goal: String, Codable, CaseIterable, Hashable, Sendable {
    case strength, hypertrophy, general
}

public enum TrainingLocation: String, Codable, CaseIterable, Hashable, Sendable {
    case gym, home, mixed
}

public struct Exercise: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var nameEn: String
    public var nameZh: String?
    public var equipment: Equipment
    public var loadType: LoadType
    public var primaryMuscles: [Muscle]
    public var secondaryMuscles: [Muscle]
    /// Other names to search by, such as "RDL" or "卧推".
    public var aliases: [String]
    /// The built-in exercise a custom one is a variant of.
    public var baseExerciseId: UUID?
    public var isCustom: Bool

    public init(
        id: UUID = UUID(),
        nameEn: String,
        nameZh: String? = nil,
        equipment: Equipment,
        loadType: LoadType,
        primaryMuscles: [Muscle],
        secondaryMuscles: [Muscle] = [],
        aliases: [String] = [],
        baseExerciseId: UUID? = nil,
        isCustom: Bool
    ) {
        self.id = id
        self.nameEn = nameEn
        self.nameZh = nameZh
        self.equipment = equipment
        self.loadType = loadType
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.aliases = aliases
        self.baseExerciseId = baseExerciseId
        self.isCustom = isCustom
    }

    /// The name in the app's language; Chinese falls back to English.
    public func name(chinese: Bool) -> String {
        chinese ? (nameZh ?? nameEn) : nameEn
    }
}

public struct WorkoutSet: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var setType: SetType
    public var reps: Int?
    public var weightKg: Double?
    /// Reps in reserve.
    public var rir: Int?
    public var durationSeconds: Int?
    /// Nil while the set is only planned.
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        setType: SetType = .working,
        reps: Int? = nil,
        weightKg: Double? = nil,
        rir: Int? = nil,
        durationSeconds: Int? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.setType = setType
        self.reps = reps
        self.weightKg = weightKg
        self.rir = rir
        self.durationSeconds = durationSeconds
        self.completedAt = completedAt
    }

    public var isCompleted: Bool { completedAt != nil }
}

public struct WorkoutExercise: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var exerciseId: UUID
    public var notes: String?
    public var supersetGroup: Int?
    public var restSeconds: Int?
    public var sets: [WorkoutSet]

    public init(
        id: UUID = UUID(),
        exerciseId: UUID,
        notes: String? = nil,
        supersetGroup: Int? = nil,
        restSeconds: Int? = nil,
        sets: [WorkoutSet] = []
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.notes = notes
        self.supersetGroup = supersetGroup
        self.restSeconds = restSeconds
        self.sets = sets
    }
}

public struct Workout: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var templateId: UUID?
    public var startedAt: Date
    /// Nil while the workout is in progress.
    public var endedAt: Date?
    /// IANA name of the time zone the workout happened in.
    public var timeZone: String
    public var notes: String?
    public var avgHeartRate: Int?
    public var maxHeartRate: Int?
    public var healthkitWorkoutId: String?
    public var exercises: [WorkoutExercise]

    public init(
        id: UUID = UUID(),
        title: String,
        templateId: UUID? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        timeZone: String = TimeZone.current.identifier,
        notes: String? = nil,
        avgHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        healthkitWorkoutId: String? = nil,
        exercises: [WorkoutExercise] = []
    ) {
        self.id = id
        self.title = title
        self.templateId = templateId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timeZone = timeZone
        self.notes = notes
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.healthkitWorkoutId = healthkitWorkoutId
        self.exercises = exercises
    }

    public var isInProgress: Bool { endedAt == nil }
}

public struct TemplateSet: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var setType: SetType
    public var repMin: Int?
    public var repMax: Int?
    public var targetRir: Int?

    public init(
        id: UUID = UUID(),
        setType: SetType = .working,
        repMin: Int? = nil,
        repMax: Int? = nil,
        targetRir: Int? = nil
    ) {
        self.id = id
        self.setType = setType
        self.repMin = repMin
        self.repMax = repMax
        self.targetRir = targetRir
    }
}

public struct TemplateExercise: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var exerciseId: UUID
    public var restSeconds: Int?
    public var supersetGroup: Int?
    public var sets: [TemplateSet]

    public init(
        id: UUID = UUID(),
        exerciseId: UUID,
        restSeconds: Int? = nil,
        supersetGroup: Int? = nil,
        sets: [TemplateSet] = []
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.restSeconds = restSeconds
        self.supersetGroup = supersetGroup
        self.sets = sets
    }
}

public struct TemplateDay: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// Only built-in templates have one.
    public var nameZh: String?
    public var exercises: [TemplateExercise]

    public init(id: UUID = UUID(), name: String, nameZh: String? = nil, exercises: [TemplateExercise] = []) {
        self.id = id
        self.name = name
        self.nameZh = nameZh
        self.exercises = exercises
    }

    public func name(chinese: Bool) -> String {
        chinese ? (nameZh ?? name) : name
    }
}

public struct Template: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var nameEn: String
    public var nameZh: String?
    public var level: Level?
    public var daysPerWeek: Int?
    public var notes: String?
    public var days: [TemplateDay]
    public var isCustom: Bool

    public init(
        id: UUID = UUID(),
        nameEn: String,
        nameZh: String? = nil,
        level: Level? = nil,
        daysPerWeek: Int? = nil,
        notes: String? = nil,
        days: [TemplateDay],
        isCustom: Bool
    ) {
        self.id = id
        self.nameEn = nameEn
        self.nameZh = nameZh
        self.level = level
        self.daysPerWeek = daysPerWeek
        self.notes = notes
        self.days = days
        self.isCustom = isCustom
    }

    public func name(chinese: Bool) -> String {
        chinese ? (nameZh ?? nameEn) : nameEn
    }
}

public struct Profile: Hashable, Codable, Sendable {
    public var unitSystem: UnitSystem
    public var experienceLevel: Level?
    public var goal: Goal?
    /// Calendar date, "2001-04-30".
    public var birthday: String?
    public var heightCm: Double?
    public var gender: String?
    public var trainingLocation: TrainingLocation?
    public var trainingDaysPerWeek: Int?

    public init(
        unitSystem: UnitSystem = .metric,
        experienceLevel: Level? = nil,
        goal: Goal? = nil,
        birthday: String? = nil,
        heightCm: Double? = nil,
        gender: String? = nil,
        trainingLocation: TrainingLocation? = nil,
        trainingDaysPerWeek: Int? = nil
    ) {
        self.unitSystem = unitSystem
        self.experienceLevel = experienceLevel
        self.goal = goal
        self.birthday = birthday
        self.heightCm = heightCm
        self.gender = gender
        self.trainingLocation = trainingLocation
        self.trainingDaysPerWeek = trainingDaysPerWeek
    }
}

// Fields the API may leave out because they have a default there (its schema does not
// list them as required). Decoding falls back to the same default, so an older or newer
// backend that omits one does not stop the sync.

extension Exercise {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(UUID.self, forKey: .id),
            nameEn: c.decode(String.self, forKey: .nameEn),
            nameZh: c.decodeIfPresent(String.self, forKey: .nameZh),
            equipment: c.decode(Equipment.self, forKey: .equipment),
            loadType: c.decode(LoadType.self, forKey: .loadType),
            primaryMuscles: c.decode([Muscle].self, forKey: .primaryMuscles),
            secondaryMuscles: c.decodeIfPresent([Muscle].self, forKey: .secondaryMuscles) ?? [],
            aliases: c.decodeIfPresent([String].self, forKey: .aliases) ?? [],
            baseExerciseId: c.decodeIfPresent(UUID.self, forKey: .baseExerciseId),
            isCustom: c.decode(Bool.self, forKey: .isCustom)
        )
    }
}

extension WorkoutSet {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(UUID.self, forKey: .id),
            setType: c.decodeIfPresent(SetType.self, forKey: .setType) ?? .working,
            reps: c.decodeIfPresent(Int.self, forKey: .reps),
            weightKg: c.decodeIfPresent(Double.self, forKey: .weightKg),
            rir: c.decodeIfPresent(Int.self, forKey: .rir),
            durationSeconds: c.decodeIfPresent(Int.self, forKey: .durationSeconds),
            completedAt: c.decodeIfPresent(Date.self, forKey: .completedAt)
        )
    }
}

extension TemplateSet {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(UUID.self, forKey: .id),
            setType: c.decodeIfPresent(SetType.self, forKey: .setType) ?? .working,
            repMin: c.decodeIfPresent(Int.self, forKey: .repMin),
            repMax: c.decodeIfPresent(Int.self, forKey: .repMax),
            targetRir: c.decodeIfPresent(Int.self, forKey: .targetRir)
        )
    }
}

extension Profile {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            unitSystem: c.decodeIfPresent(UnitSystem.self, forKey: .unitSystem) ?? .metric,
            experienceLevel: c.decodeIfPresent(Level.self, forKey: .experienceLevel),
            goal: c.decodeIfPresent(Goal.self, forKey: .goal),
            birthday: c.decodeIfPresent(String.self, forKey: .birthday),
            heightCm: c.decodeIfPresent(Double.self, forKey: .heightCm),
            gender: c.decodeIfPresent(String.self, forKey: .gender),
            trainingLocation: c.decodeIfPresent(TrainingLocation.self, forKey: .trainingLocation),
            trainingDaysPerWeek: c.decodeIfPresent(Int.self, forKey: .trainingDaysPerWeek)
        )
    }
}

extension Profile {
    private static func birthdayFormat() -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC")!).year().month().day()
    }

    /// `birthday` as a date (midnight UTC), for date pickers.
    public var birthdayDate: Date? {
        get { birthday.flatMap { try? Self.birthdayFormat().parse($0) } }
        set { birthday = newValue.map { Self.birthdayFormat().format($0) } }
    }

    /// Height in inches for people who use pounds.
    public var heightInches: Double? {
        get { heightCm.map { ($0 / 2.54 * 10).rounded() / 10 } }
        set { heightCm = newValue.map { ($0 * 2.54 * 10).rounded() / 10 } }
    }
}
