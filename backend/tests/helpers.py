import uuid

from catalog import exercise_id

BENCH = str(exercise_id("barbell_bench_press"))
SQUAT = str(exercise_id("back_squat"))


def new_id() -> str:
    return str(uuid.uuid4())


def workout_body(*, exercise: str = BENCH, sets: int = 3, weight: str = "60", **overrides):
    body = {
        "title": "Push day",
        "started_at": "2026-10-20T18:00:00+02:00",
        "ended_at": "2026-10-20T19:05:00+02:00",
        "time_zone": "Europe/Berlin",
        "exercises": [
            {
                "id": new_id(),
                "exercise_id": exercise,
                "rest_seconds": 150,
                "sets": [
                    {
                        "id": new_id(),
                        "set_type": "working",
                        "reps": 8,
                        "weight_kg": weight,
                        "rir": 2,
                        "completed_at": "2026-10-20T18:10:00+02:00",
                    }
                    for _ in range(sets)
                ],
            }
        ],
    }
    body.update(overrides)
    return body
