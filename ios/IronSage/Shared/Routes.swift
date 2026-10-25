import Foundation

// Navigation values. Separate types keep a template's id and a workout's id apart when
// both screens can be pushed onto the same stack (Today shows both).

struct WorkoutRoute: Hashable {
    let id: UUID
}

struct TemplateRoute: Hashable {
    let id: UUID
}

struct TemplateListRoute: Hashable {}

struct ExerciseRoute: Hashable {
    let id: UUID
}
