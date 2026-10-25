"""Built-in training templates, written for IronSage from docs/coaching.md.

Like catalog.py, this list is the source of truth: `sync_builtin_templates` writes it to
the database after migrations on every deploy. IDs come from the slugs, so never rename
a slug. Run catalog.py first: templates refer to its exercises.

The rules they follow (coaching.md): main lifts 3–6 reps at 1–3 reps in reserve,
accessories 6–15 reps at 0–2, every muscle at least twice a week, 3 minutes of rest for
compound lifts and 90 seconds for isolation work.

Run by hand with: python template_catalog.py
"""

import uuid
from typing import NamedTuple

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from catalog import exercise_id
from models import Template, TemplateDay, TemplateExercise, utcnow
from schemas import (
    TemplateDayWrite,
    TemplateExerciseWrite,
    TemplateSetWrite,
    TemplateWrite,
)
from sync import template_days

TEMPLATE_NAMESPACE = uuid.UUID("2d7e5c1a-8b44-4f6e-9c3d-7a1b0e5f9d22")

COMPOUND_REST = 180
ISOLATION_REST = 90


class Item(NamedTuple):
    exercise: str
    sets: int
    rep_min: int
    rep_max: int
    rir: int
    rest: int = COMPOUND_REST


class Day(NamedTuple):
    slug: str
    name_en: str
    name_zh: str
    items: tuple[Item, ...]


class BuiltinTemplate(NamedTuple):
    slug: str
    name_en: str
    name_zh: str
    level: str
    days_per_week: int
    days: tuple[Day, ...]


def iso(exercise: str, sets: int, rep_min: int, rep_max: int, rir: int = 1) -> Item:
    return Item(exercise, sets, rep_min, rep_max, rir, ISOLATION_REST)


BUILTIN_TEMPLATES: tuple[BuiltinTemplate, ...] = (
    BuiltinTemplate(
        "beginner_full_body", "Beginner full body", "新手全身训练", "beginner", 3,
        (
            Day("a", "Day A", "A 日", (
                Item("back_squat", 3, 5, 5, 2),
                Item("barbell_bench_press", 3, 5, 5, 2),
                Item("barbell_row", 3, 8, 10, 2),
                iso("dumbbell_curl", 2, 10, 12),
            )),
            Day("b", "Day B", "B 日", (
                Item("deadlift", 2, 5, 5, 2),
                Item("overhead_press", 3, 5, 5, 2),
                Item("lat_pulldown", 3, 8, 10, 2),
                Item("leg_press", 2, 10, 12, 2),
                iso("tricep_pushdown", 2, 10, 12),
            )),
        ),
    ),
    BuiltinTemplate(
        "upper_lower", "Upper / lower", "上下肢分化", "intermediate", 4,
        (
            Day("upper_heavy", "Upper (heavy)", "上肢（大重量）", (
                Item("barbell_bench_press", 4, 4, 6, 2),
                Item("barbell_row", 4, 6, 8, 2),
                Item("overhead_press", 3, 6, 8, 2),
                Item("lat_pulldown", 3, 8, 10, 2),
                iso("dumbbell_curl", 2, 10, 12),
                iso("tricep_pushdown", 2, 10, 12),
            )),
            Day("lower_heavy", "Lower (heavy)", "下肢（大重量）", (
                Item("back_squat", 4, 4, 6, 2),
                Item("romanian_deadlift", 3, 6, 8, 2),
                Item("leg_press", 3, 8, 10, 2),
                iso("lying_leg_curl", 3, 10, 12),
                iso("standing_calf_raise", 3, 10, 15),
            )),
            Day("upper_moderate", "Upper (moderate)", "上肢（中等重量）", (
                Item("incline_dumbbell_bench_press", 3, 8, 12, 2),
                Item("seated_cable_row", 3, 8, 12, 2),
                Item("dumbbell_shoulder_press", 3, 8, 12, 2),
                Item("pull_up", 3, 6, 10, 2),
                iso("lateral_raise", 3, 12, 15),
                iso("face_pull", 2, 12, 15),
            )),
            Day("lower_moderate", "Lower (moderate)", "下肢（中等重量）", (
                Item("deadlift", 3, 3, 5, 2),
                Item("bulgarian_split_squat", 3, 8, 10, 2),
                Item("hip_thrust", 3, 8, 12, 2),
                iso("leg_extension", 3, 10, 15),
                iso("seated_leg_curl", 3, 10, 15),
                iso("seated_calf_raise", 3, 12, 15),
            )),
        ),
    ),
    BuiltinTemplate(
        "push_pull_legs", "Push / pull / legs", "推拉腿", "intermediate", 6,
        (
            Day("push", "Push", "推", (
                Item("barbell_bench_press", 4, 5, 8, 2),
                Item("overhead_press", 3, 6, 10, 2),
                Item("incline_dumbbell_bench_press", 3, 8, 12, 2),
                iso("cable_fly", 2, 12, 15),
                iso("lateral_raise", 3, 12, 20),
                iso("tricep_pushdown", 3, 10, 15),
            )),
            Day("pull", "Pull", "拉", (
                Item("barbell_row", 4, 6, 10, 2),
                Item("pull_up", 3, 6, 10, 2),
                Item("seated_cable_row", 3, 8, 12, 2),
                iso("face_pull", 3, 12, 15),
                iso("hammer_curl", 3, 10, 12),
                iso("barbell_curl", 2, 8, 12),
            )),
            Day("legs", "Legs", "腿", (
                Item("back_squat", 4, 5, 8, 2),
                Item("romanian_deadlift", 3, 8, 10, 2),
                Item("leg_press", 3, 10, 12, 2),
                iso("lying_leg_curl", 3, 10, 15),
                iso("standing_calf_raise", 4, 10, 15),
                iso("hanging_leg_raise", 3, 10, 15),
            )),
        ),
    ),
    BuiltinTemplate(
        "strength_upper_lower", "Strength upper / lower", "力量上下肢分化", "intermediate", 4,
        (
            Day("upper_heavy", "Upper (heavy)", "上肢（大重量）", (
                Item("barbell_bench_press", 5, 3, 5, 2),
                Item("barbell_row", 4, 4, 6, 2),
                Item("overhead_press", 3, 4, 6, 2),
                Item("chin_up", 3, 5, 8, 2),
                Item("close_grip_bench_press", 3, 6, 8, 2),
            )),
            Day("lower_heavy", "Lower (heavy)", "下肢（大重量）", (
                Item("back_squat", 5, 3, 5, 2),
                Item("deadlift", 3, 3, 5, 2),
                Item("romanian_deadlift", 3, 6, 8, 2),
                iso("hanging_leg_raise", 3, 10, 12),
            )),
            Day("upper_moderate", "Upper (moderate)", "上肢（中等重量）", (
                Item("barbell_bench_press", 4, 6, 8, 2),
                Item("pendlay_row", 4, 6, 8, 2),
                Item("dumbbell_shoulder_press", 3, 8, 10, 2),
                Item("lat_pulldown", 3, 8, 10, 2),
                iso("skull_crusher", 3, 8, 12),
                iso("ez_bar_curl", 3, 8, 12),
            )),
            Day("lower_moderate", "Lower (moderate)", "下肢（中等重量）", (
                Item("front_squat", 4, 5, 8, 2),
                Item("romanian_deadlift", 3, 8, 10, 2),
                Item("walking_lunge", 3, 10, 12, 2),
                iso("seated_leg_curl", 3, 10, 12),
                iso("standing_calf_raise", 3, 10, 15),
            )),
        ),
    ),
)  # fmt: skip


def template_id(slug: str) -> uuid.UUID:
    return uuid.uuid5(TEMPLATE_NAMESPACE, f"template:{slug}")


def _id(*parts: object) -> uuid.UUID:
    return uuid.uuid5(TEMPLATE_NAMESPACE, ":".join(str(part) for part in parts))


def template_write(entry: BuiltinTemplate) -> TemplateWrite:
    return TemplateWrite(
        name_en=entry.name_en,
        name_zh=entry.name_zh,
        level=entry.level,
        days_per_week=entry.days_per_week,
        days=[
            TemplateDayWrite(
                id=_id(entry.slug, day.slug),
                name=day.name_en,
                name_zh=day.name_zh,
                exercises=[
                    TemplateExerciseWrite(
                        id=_id(entry.slug, day.slug, position),
                        exercise_id=exercise_id(item.exercise),
                        rest_seconds=item.rest,
                        sets=[
                            TemplateSetWrite(
                                id=_id(entry.slug, day.slug, position, number),
                                rep_min=item.rep_min,
                                rep_max=item.rep_max,
                                target_rir=item.rir,
                            )
                            for number in range(item.sets)
                        ],
                    )
                    for position, item in enumerate(day.items)
                ],
            )
            for day in entry.days
        ],
    )


def _as_written(template: Template) -> dict:
    """The stored template in the shape of TemplateWrite, to compare with the list."""
    return TemplateWrite.model_validate(
        {
            "name_en": template.name_en,
            "name_zh": template.name_zh,
            "level": template.level,
            "days_per_week": template.days_per_week,
            "notes": template.notes,
            "days": [
                {
                    "id": day.id,
                    "name": day.name,
                    "name_zh": day.name_zh,
                    "exercises": [
                        {
                            "id": exercise.id,
                            "exercise_id": exercise.exercise_id,
                            "rest_seconds": exercise.rest_seconds,
                            "superset_group": exercise.superset_group,
                            "sets": [
                                {
                                    "id": template_set.id,
                                    "set_type": template_set.set_type,
                                    "rep_min": template_set.rep_min,
                                    "rep_max": template_set.rep_max,
                                    "target_rir": template_set.target_rir,
                                }
                                for template_set in exercise.sets
                            ],
                        }
                        for exercise in day.exercises
                    ],
                }
                for day in template.days
            ],
        }
    ).model_dump()


def sync_builtin_templates(db: Session) -> dict[str, int]:
    """Makes the built-in rows in `templates` match BUILTIN_TEMPLATES."""
    existing = {
        row.id: row
        for row in db.scalars(
            select(Template)
            .options(
                selectinload(Template.days)
                .selectinload(TemplateDay.exercises)
                .selectinload(TemplateExercise.sets)
            )
            .where(Template.owner_user_id.is_(None))
        )
    }
    counts = {"added": 0, "updated": 0, "removed": 0}

    for entry in BUILTIN_TEMPLATES:
        wanted = template_write(entry)
        row = existing.pop(template_id(entry.slug), None)
        if row is None:
            row = Template(id=template_id(entry.slug), owner_user_id=None)
            db.add(row)
            counts["added"] += 1
        elif row.deleted_at is None and _as_written(row) == wanted.model_dump():
            continue
        else:
            counts["updated"] += 1
            row.days.clear()
            db.flush()
        for field, value in wanted.model_dump(exclude={"days"}).items():
            setattr(row, field, value)
        row.days = template_days(wanted)
        row.deleted_at = None
        row.updated_at = utcnow()

    for row in existing.values():
        if row.deleted_at is None:
            row.deleted_at = utcnow()
            counts["removed"] += 1

    db.commit()
    return counts


if __name__ == "__main__":
    from database import SessionLocal

    with SessionLocal() as session:
        print(sync_builtin_templates(session))
