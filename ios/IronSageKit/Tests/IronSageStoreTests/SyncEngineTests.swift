import Foundation
import IronSageAPI
import IronSageCore
import Testing

@testable import IronSageStore

@MainActor
private struct Harness {
    let store: LocalStore
    let server: FakeServer
    let sync: SyncEngine
    let defaults: UserDefaults

    init(_ respond: @escaping FakeServer.Responder = FakeServer.standard) throws {
        store = try LocalStore(inMemory: true)
        server = FakeServer(respond)
        defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        let api = Client.ironSage(
            serverURL: URL(string: "https://api.example.com")!,
            token: { "token" },
            transport: server
        )
        sync = SyncEngine(store: store, api: api, defaults: defaults)
    }
}

private let bench = UUID(uuidString: FakeServer.benchID)!

private func pushDay(completed: Bool = true) -> Workout {
    Workout(
        title: "Push day",
        startedAt: Date(timeIntervalSince1970: 1_792_850_000),
        endedAt: completed ? Date(timeIntervalSince1970: 1_792_853_900) : nil,
        timeZone: "Europe/Berlin",
        exercises: [
            WorkoutExercise(
                exerciseId: bench,
                restSeconds: 180,
                sets: [WorkoutSet(reps: 8, weightKg: 61.235, rir: 2, completedAt: Date(timeIntervalSince1970: 1_792_850_600))]
            ),
        ]
    )
}

@MainActor
@Test func savedWorkoutsAreUploadedInTheAPIsShape() async throws {
    let harness = try Harness()
    let workout = pushDay()
    harness.store.save(workout)

    await harness.sync.sync()

    #expect(harness.sync.state == .idle)
    let put = try #require(harness.server.requests.first { $0.method == .put })
    #expect(put.path == "/v1/workouts/\(workout.id.uuidString.lowercased())")
    let body = put.json
    #expect(body["time_zone"] as? String == "Europe/Berlin")
    #expect(body["started_at"] as? String == "2026-10-24T13:53:20.000Z")
    let exercise = try #require((body["exercises"] as? [[String: Any]])?.first)
    #expect(exercise["rest_seconds"] as? Int == 180)
    let set = try #require((exercise["sets"] as? [[String: Any]])?.first)
    #expect(set["weight_kg"] as? Double == 61.235)
    #expect(set["set_type"] as? String == "working")
    #expect(harness.store.pendingChanges().isEmpty)
}

@MainActor
@Test func pullingAppliesEveryPageAndSavesTheCursor() async throws {
    let first = UUID().uuidString.lowercased()
    let second = UUID().uuidString.lowercased()
    let hidden = UUID().uuidString.lowercased()
    let harness = try Harness { request in
        guard request.path.hasPrefix("/v1/sync") else { return try FakeServer.standard(request) }
        if request.path.contains("since=0") {
            return (200, FakeServer.syncPage(
                changeSeq: 4, hasMore: true,
                workouts: [FakeServer.workoutJSON(id: first, title: "Legs", changeSeq: 4)]
            ))
        }
        #expect(request.path.contains("since=4"))
        return (200, FakeServer.syncPage(
            changeSeq: 9,
            workouts: [FakeServer.workoutJSON(id: second, title: "Pull", changeSeq: 9)],
            profile: #"{"unit_system": "imperial", "hidden_template_ids": ["\#(hidden)"], "updated_at": "2026-10-25T10:00:00Z", "change_seq": 7}"#
        ))
    }

    await harness.sync.sync()

    #expect(harness.sync.state == .idle)
    #expect(Set(harness.store.workouts.map(\.title)) == ["Legs", "Pull"])
    #expect(harness.store.workouts[0].exercises[0].sets[0].weightKg == 61.235)
    #expect(harness.store.profile?.unitSystem == .imperial)
    #expect(harness.store.profile?.hiddenTemplateIds.map(\.uuidString) == [hidden.uppercased()])
    #expect(harness.defaults.integer(forKey: SyncEngine.Keys.changeSeq) == 9)
}

@MainActor
@Test func remoteDeletionsRemoveWorkouts() async throws {
    let id = UUID()
    let harness = try Harness { request in
        guard request.path.hasPrefix("/v1/sync") else { return try FakeServer.standard(request) }
        return (200, FakeServer.syncPage(
            changeSeq: 3,
            workouts: [FakeServer.workoutJSON(id: id.uuidString.lowercased(), title: "Old", changeSeq: 3, deleted: true)]
        ))
    }
    var workout = pushDay()
    workout.id = id
    harness.store.applyRemote(.workout(workout), id: id, changeSeq: 1, deleted: false)

    await harness.sync.sync()

    #expect(harness.store.workouts.isEmpty)
}

@MainActor
@Test func unsentLocalEditsWinOverTheServer() async throws {
    let harness = try Harness()
    var workout = pushDay()
    harness.store.applyRemote(.workout(workout), id: workout.id, changeSeq: 1, deleted: false)
    workout.title = "Edited on the phone"
    harness.store.save(workout)

    var remote = workout
    remote.title = "Edited elsewhere"
    harness.store.applyRemote(.workout(remote), id: workout.id, changeSeq: 2, deleted: false)

    #expect(harness.store.workouts.first?.title == "Edited on the phone")
    #expect(harness.store.pendingChanges().count == 1)
}

@MainActor
@Test func anEditDuringTheUploadStaysPending() throws {
    let harness = try Harness()
    var workout = pushDay()
    harness.store.save(workout)
    let sent = try #require(harness.store.pendingChanges().first)

    workout.title = "Renamed while uploading"
    harness.store.save(workout)
    harness.store.markUploaded(sent, changeSeq: 5)

    #expect(harness.store.pendingChanges().count == 1)
}

@MainActor
@Test func deletingANewWorkoutStillTellsTheServer() async throws {
    // Its first upload may have reached the server without the reply reaching the phone.
    let harness = try Harness { request in
        request.method == .delete ? (404, #"{"detail": "Workout not found"}"#) : try FakeServer.standard(request)
    }
    let workout = pushDay()
    harness.store.save(workout)
    harness.store.deleteWorkout(id: workout.id)

    await harness.sync.sync()

    let workoutRequests = harness.server.requests.filter { $0.path.hasPrefix("/v1/workouts") }
    #expect(workoutRequests.map(\.method) == [.delete])
    #expect(harness.store.workouts.isEmpty)
    #expect(harness.store.pendingChanges().isEmpty)
}

@MainActor
@Test func customExercisesGoUpBeforeTheWorkoutsThatUseThem() async throws {
    let harness = try Harness()
    var workout = pushDay(completed: false)
    harness.store.save(workout)
    let machine = Exercise(nameEn: "Hack squat (gym)", equipment: .machine, loadType: .total, primaryMuscles: [.quads], isCustom: true)
    harness.store.save(machine)
    workout.exercises.append(WorkoutExercise(exerciseId: machine.id))
    harness.store.save(workout)

    await harness.sync.sync()

    let puts = harness.server.requests.filter { $0.method == .put }.map(\.path)
    #expect(puts == ["/v1/exercises/\(machine.id.uuidString.lowercased())", "/v1/workouts/\(workout.id.uuidString.lowercased())"])
}

@MainActor
@Test func aSyncRequestedDuringASyncRunsAfterIt() async throws {
    let harness = try Harness()
    harness.store.save(pushDay())

    async let first: Void = harness.sync.sync()
    await Task.yield()
    harness.store.save(pushDay())
    await harness.sync.sync()
    await first

    #expect(harness.store.pendingChanges().isEmpty)
    #expect(harness.server.requests.filter { $0.method == .put }.count == 2)
}

@MainActor
@Test func resetStopsARunningSync() async throws {
    let harness = try Harness { request in
        guard request.path.hasPrefix("/v1/sync") else { return try FakeServer.standard(request) }
        return (200, FakeServer.syncPage(
            changeSeq: 5,
            workouts: [FakeServer.workoutJSON(id: UUID().uuidString.lowercased(), title: "Someone else's", changeSeq: 5)]
        ))
    }

    async let running: Void = harness.sync.sync()
    await Task.yield()
    harness.store.removeAll()
    harness.sync.reset()
    await running

    #expect(harness.store.workouts.isEmpty)
    #expect(harness.defaults.object(forKey: SyncEngine.Keys.changeSeq) == nil)
}

@MainActor
@Test func deletingAnUploadedWorkoutSendsADelete() async throws {
    let harness = try Harness { request in
        // Someone already deleted it elsewhere: still done.
        request.method == .delete ? (404, #"{"detail": "Workout not found"}"#) : try FakeServer.standard(request)
    }
    let workout = pushDay()
    harness.store.applyRemote(.workout(workout), id: workout.id, changeSeq: 1, deleted: false)
    harness.store.deleteWorkout(id: workout.id)

    await harness.sync.sync()

    let delete = try #require(harness.server.requests.first { $0.method == .delete })
    #expect(delete.path == "/v1/workouts/\(workout.id.uuidString.lowercased())")
    #expect(harness.store.pendingChanges().isEmpty)
    #expect(harness.sync.state == .idle)
}

@MainActor
@Test func rejectedChangesAreNotRetriedButServerErrorsAre() async throws {
    let harness = try Harness { request in
        request.method == .put ? (422, #"{"detail": "Unknown exercise"}"#) : try FakeServer.standard(request)
    }
    harness.store.save(pushDay())

    await harness.sync.sync()
    #expect(harness.store.pendingChanges().isEmpty)
    #expect(harness.store.workouts.count == 1)

    harness.server.respond { request in
        request.method == .put ? (503, #"{"detail": "Service Unavailable"}"#) : try FakeServer.standard(request)
    }
    harness.store.save(pushDay())
    await harness.sync.sync()
    #expect(harness.sync.state == .failed)
    #expect(harness.store.pendingChanges().count == 1)
}

@MainActor
@Test func withoutAConnectionEditsWait() async throws {
    let harness = try Harness { _ in throw URLError(.notConnectedToInternet) }
    harness.store.save(pushDay(completed: false))

    await harness.sync.sync()

    #expect(harness.sync.state == .offline)
    #expect(harness.store.pendingChanges().count == 1)
    #expect(harness.store.activeWorkout != nil)
    #expect(harness.sync.lastSyncedAt == nil)
}

@MainActor
@Test func theCatalogIsFetchedOnceADayAndRetiredExercisesStayReadable() async throws {
    let harness = try Harness()

    await harness.sync.sync()
    await harness.sync.sync()

    #expect(harness.server.requests.filter { $0.path == "/v1/exercises" }.count == 1)
    let fetched = try #require(harness.store.exercises[bench])
    #expect(fetched.aliases == ["bench", "卧推"])
    #expect(fetched.secondaryMuscles == [.frontDelts, .triceps])
    #expect(harness.store.availableExercises.map(\.id) == [bench])

    harness.store.replaceBuiltInExercises([])
    #expect(harness.store.exercises[bench]?.nameZh == "杠铃卧推")
    #expect(harness.store.availableExercises.isEmpty)
}

@MainActor
@Test func builtInTemplatesComeWithTheCatalog() async throws {
    let harness = try Harness()

    await harness.sync.sync()

    let template = try #require(harness.store.templates.first)
    #expect(template.id == UUID(uuidString: FakeServer.templateID))
    #expect(!template.isCustom)
    #expect(template.days[0].name(chinese: true) == "推")
    #expect(template.days[0].exercises[0].sets[0].repMax == 8)
    #expect(harness.store.pendingChanges().isEmpty)

    harness.store.replaceBuiltInTemplates([])
    #expect(harness.store.templates.isEmpty)
}

@MainActor
@Test func customExercisesAndProfilesAreUploaded() async throws {
    let harness = try Harness()
    let machine = Exercise(
        nameEn: "Hammer Strength chest press", equipment: .machine, loadType: .perSide,
        primaryMuscles: [.chest], aliases: ["HS press"], baseExerciseId: bench, isCustom: true
    )
    harness.store.save(machine)
    let hidden = UUID()
    harness.store.save(Profile(unitSystem: .imperial, experienceLevel: .beginner, hiddenTemplateIds: [hidden]))

    await harness.sync.sync()

    let exercisePut = try #require(harness.server.requests.first { $0.path.hasPrefix("/v1/exercises/") })
    #expect(exercisePut.json["load_type"] as? String == "per_side")
    #expect(exercisePut.json["base_exercise_id"] as? String == FakeServer.benchID.uppercased())
    #expect(exercisePut.json["aliases"] as? [String] == ["HS press"])
    let profilePut = try #require(harness.server.requests.first { $0.path == "/v1/profile" })
    #expect(profilePut.json["unit_system"] as? String == "imperial")
    #expect(profilePut.json["experience_level"] as? String == "beginner")
    #expect(profilePut.json["hidden_template_ids"] as? [String] == [hidden.uuidString])
}

@MainActor
@Test func hidingAProgramUploadsTheProfile() async throws {
    let harness = try Harness()
    let program = UUID()
    let other = UUID()
    harness.store.save(Profile(unitSystem: .metric))
    harness.store.setTemplate(program, hidden: true)
    harness.store.setTemplate(other, hidden: true)
    harness.store.setTemplate(program, hidden: true)
    harness.store.setTemplate(other, hidden: false)

    await harness.sync.sync()

    #expect(harness.store.profile?.hiddenTemplateIds == [program])
    let profilePut = try #require(harness.server.requests.last { $0.path == "/v1/profile" })
    #expect(profilePut.json["hidden_template_ids"] as? [String] == [program.uuidString])
}

@MainActor
@Test func removingAllDataStartsOver() async throws {
    let harness = try Harness()
    harness.store.save(pushDay())
    await harness.sync.sync()

    harness.store.removeAll()
    harness.sync.reset()

    #expect(harness.store.workouts.isEmpty)
    #expect(harness.store.exercises.isEmpty)
    #expect(harness.defaults.object(forKey: SyncEngine.Keys.changeSeq) == nil)
    #expect(harness.sync.lastSyncedAt == nil)
}

@MainActor
@Test func fieldsWithAnAPIDefaultMayBeMissing() async throws {
    // A backend from before aliases existed, and sets and profiles without the fields
    // that have defaults.
    let oldBench = FakeServer.benchJSON.replacingOccurrences(of: #""aliases": ["bench", "卧推"],"#, with: "")
        .replacingOccurrences(of: #""secondary_muscles": ["front_delts", "triceps"],"#, with: "")
    let workout = FakeServer.workoutJSON(id: UUID().uuidString.lowercased(), title: "Old", changeSeq: 2)
        .replacingOccurrences(of: #""set_type": "working","#, with: "")
    let harness = try Harness { request in
        if request.path == "/v1/exercises" { return (200, "[\(oldBench)]") }
        if request.path.hasPrefix("/v1/sync") {
            return (200, FakeServer.syncPage(
                changeSeq: 2, workouts: [workout],
                profile: #"{"updated_at": "2026-10-25T10:00:00Z", "change_seq": 1}"#
            ))
        }
        return try FakeServer.standard(request)
    }

    await harness.sync.sync()

    #expect(harness.sync.state == .idle)
    #expect(harness.store.exercises[bench]?.aliases == [])
    #expect(harness.store.exercises[bench]?.secondaryMuscles == [])
    #expect(harness.store.workouts.first?.exercises[0].sets[0].setType == .working)
    #expect(harness.store.profile?.unitSystem == .metric)
    #expect(harness.store.profile?.hiddenTemplateIds == [])
}

@MainActor
@Test func bodyMeasurementsAndReadinessGoUpInTheAPIsShape() async throws {
    let harness = try Harness { request in
        if request.method == .put, request.path.hasPrefix("/v1/readiness/") {
            let date = String(request.path.split(separator: "/").last ?? "")
            return (200, #"{"id": "\#(UUID().uuidString.lowercased())", "date": "\#(date)", "sleep_minutes": 432, "source": "healthkit", "updated_at": "2026-11-25T08:00:00Z", "deleted_at": null, "change_seq": 4}"#)
        }
        return try FakeServer.standard(request)
    }
    let weight = BodyMeasurement(measuredAt: Date(timeIntervalSince1970: 1_795_000_000), value: 81.4, source: .manual)
    harness.store.save(weight)
    harness.store.save(Readiness(date: "2026-11-25", sleepMinutes: 432, deepMinutes: 61, hrvSdnnMs: 42.8, restingHrBpm: 58))

    await harness.sync.sync()

    #expect(harness.sync.state == .idle)
    let weightPut = try #require(harness.server.requests.first { $0.path.hasPrefix("/v1/body-measurements/") })
    #expect(weightPut.path == "/v1/body-measurements/\(weight.id.uuidString.lowercased())")
    #expect(weightPut.json["kind"] as? String == "weight")
    #expect(weightPut.json["value"] as? Double == 81.4)
    #expect(weightPut.json["source"] as? String == "manual")
    let dayPut = try #require(harness.server.requests.first { $0.path.hasPrefix("/v1/readiness/") })
    #expect(dayPut.path == "/v1/readiness/2026-11-25")
    #expect(dayPut.json["sleep_minutes"] as? Int == 432)
    #expect(dayPut.json["hrv_sdnn_ms"] as? Double == 42.8)
    #expect(harness.store.pendingChanges().isEmpty)
}

@MainActor
@Test func pulledHealthRecordsAreKeptAndDeletionsApplied() async throws {
    let kept = UUID().uuidString.lowercased(), gone = UUID().uuidString.lowercased()
    func weight(_ id: String, _ value: Double, deleted: Bool) -> String {
        #"{"id": "\#(id)", "measured_at": "2026-11-20T07:00:00Z", "kind": "weight", "value": \#(value), "source": "healthkit", "healthkit_sample_id": "ABC", "updated_at": "2026-11-20T07:00:00Z", "deleted_at": \#(deleted ? #""2026-11-21T07:00:00Z""# : "null"), "change_seq": 3}"#
    }
    let measurements = [weight(kept, 80.2, deleted: false), weight(gone, 79, deleted: true)]
    let harness = try Harness { request in
        guard request.path.hasPrefix("/v1/sync") else { return try FakeServer.standard(request) }
        return (200, FakeServer.syncPage(
            changeSeq: 6,
            bodyMeasurements: measurements,
            readiness: [#"{"id": "\#(UUID().uuidString.lowercased())", "date": "2026-11-20", "sleep_minutes": 400, "hrv_sdnn_ms": 39.5, "resting_hr_bpm": 60, "source": "healthkit", "updated_at": "2026-11-20T08:00:00Z", "deleted_at": null, "change_seq": 5}"#]
        ))
    }
    harness.store.applyRemote(.bodyMeasurement(BodyMeasurement(id: UUID(uuidString: gone)!, measuredAt: .now, value: 79, source: .healthkit)), id: UUID(uuidString: gone)!, changeSeq: 1, deleted: false)

    await harness.sync.sync()

    #expect(harness.store.bodyMeasurements.map(\.value) == [80.2])
    #expect(harness.store.bodyMeasurements.first?.healthkitSampleId == "ABC")
    #expect(harness.store.readiness["2026-11-20"]?.hrvSdnnMs == 39.5)
    #expect(harness.store.readiness["2026-11-20"]?.sleepMinutes == 400)
}

@MainActor
@Test func theFirstSyncAfterTheUpdateStartsAgainFromZero() async throws {
    let harness = try Harness()
    // An install from before M2: a cursor, but no cursor version.
    harness.defaults.set(41, forKey: SyncEngine.Keys.changeSeq)

    await harness.sync.sync()
    await harness.sync.sync()

    let syncs = harness.server.requests.filter { $0.path.hasPrefix("/v1/sync") }.map(\.path)
    #expect(syncs.first?.contains("since=0") == true)
    #expect(harness.defaults.integer(forKey: SyncEngine.Keys.cursorVersion) == SyncEngine.cursorVersion)
    // The server's cursor (0 in this fake) is kept from then on, not reset again.
    #expect(syncs.count == 2)
}

@MainActor
@Test func eachDayHasOneStableLocalID() {
    #expect(LocalStore.readinessID("2026-11-25") == LocalStore.readinessID("2026-11-25"))
    #expect(LocalStore.readinessID("2026-11-25") != LocalStore.readinessID("2026-11-26"))
}

// MARK: AI coach

private func coachRequest() -> CoachRequest {
    CoachRequest(
        language: "en", unit: "kg", goal: .hypertrophy, experience: .intermediate,
        readiness: .init(sleepMinutes: .init(value: 310, usual: 445)),
        exercises: [.init(
            exerciseId: FakeServer.benchID, name: "Barbell bench press", isCompound: true,
            change: "increase", repMin: 6, repMax: 10, stalled: false,
            plannedSets: [.init(reps: 6, weightKg: 62.5, setType: .working)],
            lastWeightKg: 60,
            recentSessions: [.init(date: "2026-10-22", sets: [.init(reps: 10, weightKg: 60, rir: 2)])]
        )]
    )
}

private func adviceJSON(id: String, status: String, changeSeq: Int, error: String? = nil) -> String {
    let output = status == "ready" ? #"""
        {"summary": "Short night, so hold today.", "model": "anthropic:claude-sonnet-5-5",
         "input_tokens": 900, "output_tokens": 80,
         "exercises": [{"exercise_id": "\#(FakeServer.benchID)", "action": "hold_weight",
           "reason": "You slept 5 h 10 min, so stay at 60 kg.",
           "sets": [{"reps": 10, "weight_kg": 60, "set_type": "working"}]}]}
        """# : "null"
    return #"{"id": "\#(id)", "for_date": "2026-10-26", "status": "\#(status)", "output": \#(output), "error": \#(error.map { "\"\($0)\"" } ?? "null"), "updated_at": "2026-10-26T07:00:00Z", "deleted_at": null, "change_seq": \#(changeSeq)}"#
}

@MainActor
@Test func aCoachRequestGoesUpAndItsAdviceComesBackThroughSync() async throws {
    let recommendation = Recommendation(forDate: "2026-10-26", request: coachRequest(), planKey: "plan", requestedAt: .now)
    let id = recommendation.id.uuidString.lowercased()
    let harness = try Harness { request in
        if request.method == .put, request.path.hasPrefix("/v1/recommendations/") {
            return (200, adviceJSON(id: id, status: "pending", changeSeq: 7))
        }
        if request.path.hasPrefix("/v1/sync") {
            return (200, FakeServer.syncPage(changeSeq: 8, recommendations: [adviceJSON(id: id, status: "ready", changeSeq: 8)]))
        }
        return try FakeServer.standard(request)
    }
    harness.store.save(recommendation)

    await harness.sync.sync()

    #expect(harness.sync.state == .idle)
    let put = try #require(harness.server.requests.first { $0.path.hasPrefix("/v1/recommendations/") })
    #expect(put.path == "/v1/recommendations/\(id)")
    #expect(put.json["for_date"] as? String == "2026-10-26")
    let input = try #require(put.json["input"] as? [String: Any])
    #expect(input["unit"] as? String == "kg")
    let sleep = (input["readiness"] as? [String: Any])?["sleep_minutes"] as? [String: Any]
    #expect(sleep?["value"] as? Double == 310)
    let plan = try #require((input["exercises"] as? [[String: Any]])?.first)
    #expect(plan["exercise_id"] as? String == FakeServer.benchID)
    #expect(plan["last_weight_kg"] as? Double == 60)
    #expect((plan["planned_sets"] as? [[String: Any]])?.first?["set_type"] as? String == "working")

    let stored = try #require(harness.store.recommendation(for: "2026-10-26"))
    #expect(stored.status == .ready)
    #expect(stored.output?.advice(for: bench)?.action == .holdWeight)
    #expect(stored.output?.advice(for: bench)?.sets.first?.weightKg == 60)
    // The phone keeps what it asked, which the server doesn't send back.
    #expect(stored.request == coachRequest())
    #expect(stored.planKey == "plan")
    // The answer is timed from when the server accepted the request.
    #expect(stored.sentAt != nil)
    #expect(harness.store.pendingChanges().isEmpty)
}

@MainActor
@Test func nothingGoesToTheCoachOnceItIsTurnedOff() async throws {
    let harness = try Harness()
    harness.store.save(Recommendation(forDate: "2026-10-26", request: coachRequest()))
    harness.sync.allowsCoach = { false }

    await harness.sync.sync()

    #expect(!harness.server.requests.contains { $0.path.hasPrefix("/v1/recommendations/") })
    #expect(harness.store.pendingChanges().isEmpty)
    #expect(harness.store.recommendation(for: "2026-10-26")?.error == "cancelled")
}

@MainActor
@Test func turningTheCoachOffCancelsQueuedRequests() throws {
    let store = try LocalStore(inMemory: true)
    store.save(Recommendation(forDate: "2026-10-26", request: coachRequest()))
    store.cancelPendingRecommendations()
    #expect(store.pendingChanges().isEmpty)
    #expect(store.recommendation(for: "2026-10-26")?.status == .failed)
}

@MainActor
@Test func aRefusedCoachRequestDoesntBlockTheSync() async throws {
    for (status, reason) in [(402, "not_allowed"), (429, "limit_reached"), (422, "invalid_request")] {
        let harness = try Harness { request in
            if request.path.hasPrefix("/v1/recommendations/") {
                return (status, #"{"detail": "No"}"#)
            }
            return try FakeServer.standard(request)
        }
        harness.store.save(Recommendation(forDate: "2026-10-26", request: coachRequest()))
        harness.store.save(pushDay())

        await harness.sync.sync()

        #expect(harness.sync.state == .idle)
        #expect(harness.store.pendingChanges().isEmpty)
        let stored = try #require(harness.store.recommendation(for: "2026-10-26"))
        #expect(stored.status == .failed && stored.error == reason)
        #expect(harness.server.requests.contains { $0.path.hasPrefix("/v1/workouts/") })
    }
}

@MainActor
@Test func aServerErrorKeepsTheCoachRequestForLater() async throws {
    let harness = try Harness { request in
        request.path.hasPrefix("/v1/recommendations/") ? (503, #"{"detail": "Down"}"#) : try FakeServer.standard(request)
    }
    harness.store.save(Recommendation(forDate: "2026-10-26", request: coachRequest()))

    await harness.sync.sync()

    #expect(harness.sync.state == .failed)
    #expect(harness.store.pendingChanges().count == 1)
    #expect(harness.store.recommendation(for: "2026-10-26")?.status == .pending)
}

@MainActor
@Test func recommendationsAreKeptAcrossLaunches() throws {
    let store = try LocalStore(inMemory: true)
    store.save(Recommendation(forDate: "2026-10-25", requestedAt: Date(timeIntervalSince1970: 1)))
    store.save(Recommendation(forDate: "2026-10-26", requestedAt: Date(timeIntervalSince1970: 2)))
    #expect(store.recommendations.map(\.forDate) == ["2026-10-26", "2026-10-25"])
    store.removeAll()
    #expect(store.recommendations.isEmpty)
}

private func summaryJSON(id: String, status: String = "ready", changeSeq: Int) -> String {
    let output = status == "ready" ? #"""
        {"summary": "You trained 3 times. Chest got 12 sets. Sleep was steady.",
         "suggestions": ["Add two sets for your back."], "deload": false,
         "model": "anthropic:claude-sonnet-5-5", "input_tokens": 1200, "output_tokens": 250}
        """# : "null"
    return #"{"id": "\#(id)", "week_start": "2026-10-19", "status": "\#(status)", "output": \#(output), "error": null, "updated_at": "2026-10-26T14:00:00Z", "deleted_at": null, "change_seq": \#(changeSeq)}"#
}

@MainActor
@Test func weeklySummariesComeThroughSync() async throws {
    let id = UUID().uuidString.lowercased()
    let harness = try Harness { request in
        guard request.path.hasPrefix("/v1/sync") else { return try FakeServer.standard(request) }
        if request.path.contains("since=0") {
            return (200, FakeServer.syncPage(changeSeq: 3, hasMore: true, weeklySummaries: [summaryJSON(id: id, status: "pending", changeSeq: 3)]))
        }
        return (200, FakeServer.syncPage(changeSeq: 4, weeklySummaries: [summaryJSON(id: id, changeSeq: 4)]))
    }

    await harness.sync.sync()

    #expect(harness.sync.state == .idle)
    let summary = try #require(harness.store.weeklySummaries.first)
    #expect(harness.store.weeklySummaries.count == 1)
    #expect(summary.weekStart == "2026-10-19" && summary.status == .ready)
    #expect(summary.output?.suggestions == ["Add two sets for your back."])
    #expect(summary.output?.deload == false)
    harness.store.removeAll()
    #expect(harness.store.weeklySummaries.isEmpty)
}

@MainActor
@Test func theCoachSettingGoesUpOnlyWhenItChanges() async throws {
    let harness = try Harness { request in
        request.path == "/v1/coach/settings" ? (200, #"{"enabled": true, "language": "zh"}"#) : try FakeServer.standard(request)
    }
    harness.store.save(CoachSettings(enabled: true, language: "zh"))
    await harness.sync.sync()

    let put = try #require(harness.server.requests.first { $0.path == "/v1/coach/settings" })
    #expect(put.method == .put)
    #expect(put.json["enabled"] as? Bool == true && put.json["language"] as? String == "zh")
    #expect(harness.store.pendingChanges().isEmpty)

    // The same again sends nothing; turning it off does.
    harness.store.save(CoachSettings(enabled: true, language: "zh"))
    #expect(harness.store.pendingChanges().isEmpty)
    harness.store.save(CoachSettings(enabled: false, language: "zh"))
    #expect(harness.store.pendingChanges().count == 1)
}
