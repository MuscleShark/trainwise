"""Built-in training templates, written for IronSage.

Like catalog.py, this list is the source of truth: `sync_builtin_templates` writes it to
the database after migrations on every deploy. IDs come from the slugs, so never rename
a slug. Run catalog.py first: templates refer to its exercises. The app shows who each
program is for and how to progress on it from its slug (ProgramGuide.swift).

Five programs per experience level, following mainstream advice (Schoenfeld's volume and
frequency meta-analyses, Stronger by Science, Renaissance Periodization, r/Fitness):
beginners train two to four days and add weight most sessions; intermediates progress
by the week with heavy and lighter days; advanced lifters get more volume, blocks that
build up to a peak, and specialization. Every muscle is trained at least twice a week.

Targets are sets and a rep range only, with no reps in reserve: few people log it.
Rest is 3 minutes for barbell lifts, 2 for other compound lifts, 90 seconds for
isolation work and 4 for the heaviest peak sets. In a superset the first exercise has
no rest and the pair's rest follows the second.

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

BARBELL_REST = 180
COMPOUND_REST = 120
ISOLATION_REST = 90
SHORT_REST = 60
PEAK_REST = 240


class Item(NamedTuple):
    exercise: str
    sets: int
    rep_min: int
    rep_max: int
    rest: int = BARBELL_REST
    superset: int | None = None


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


def mid(exercise: str, sets: int, rep_min: int, rep_max: int, group: int | None = None) -> Item:
    """A compound lift on a machine, cable, dumbbells or body weight."""
    return Item(exercise, sets, rep_min, rep_max, COMPOUND_REST, group)


def iso(
    exercise: str, sets: int, rep_min: int, rep_max: int,
    rest: int = ISOLATION_REST, group: int | None = None,
) -> Item:  # fmt: skip
    return Item(exercise, sets, rep_min, rep_max, rest, group)


def pair(group: int, item: Item) -> Item:
    """The first exercise of a superset: straight on to the second."""
    return item._replace(rest=0, superset=group)


BUILTIN_TEMPLATES: tuple[BuiltinTemplate, ...] = (
    # Beginner: two or three full-body days, simple lifts, weight added most sessions.
    BuiltinTemplate(
        "beginner_full_body", "Barbell basics", "杠铃基础", "beginner", 3,
        (
            Day("a", "Day A", "A 日", (
                Item("back_squat", 3, 5, 5),
                Item("barbell_bench_press", 3, 5, 5),
                Item("barbell_row", 3, 5, 8),
                iso("dumbbell_curl", 2, 8, 12),
                iso("hanging_knee_raise", 2, 8, 12),
            )),
            Day("b", "Day B", "B 日", (
                Item("deadlift", 2, 5, 5),
                Item("overhead_press", 3, 5, 5),
                mid("lat_pulldown", 3, 8, 10),
                mid("leg_press", 2, 10, 12),
                iso("tricep_pushdown", 2, 10, 12),
            )),
        ),
    ),
    BuiltinTemplate(
        "machine_starter", "Machine starter", "器械入门", "beginner", 3,
        (
            Day("a", "Day A", "A 日", (
                mid("leg_press", 3, 10, 12),
                mid("machine_chest_press", 3, 8, 12),
                mid("lat_pulldown", 3, 8, 12),
                iso("seated_leg_curl", 2, 10, 15),
                iso("machine_lateral_raise", 2, 12, 15),
                iso("machine_crunch", 2, 10, 15),
            )),
            Day("b", "Day B", "B 日", (
                mid("goblet_squat", 3, 8, 12),
                mid("machine_shoulder_press", 3, 8, 12),
                mid("machine_row", 3, 8, 12),
                iso("back_extension", 2, 10, 15),
                iso("cable_curl", 2, 10, 15),
                iso("tricep_pushdown", 2, 10, 15),
            )),
        ),
    ),
    BuiltinTemplate(
        "home_dumbbells", "Home dumbbells", "居家哑铃", "beginner", 3,
        (
            Day("a", "Day A", "A 日", (
                mid("goblet_squat", 3, 8, 15),
                mid("dumbbell_bench_press", 3, 8, 12),
                mid("dumbbell_row", 3, 8, 12),
                mid("dumbbell_romanian_deadlift", 3, 8, 12),
                iso("lateral_raise", 2, 12, 15),
                iso("dumbbell_curl", 2, 10, 12),
            )),
            Day("b", "Day B", "B 日", (
                mid("reverse_lunge", 3, 8, 12),
                mid("dumbbell_shoulder_press", 3, 8, 12),
                mid("dumbbell_floor_press", 3, 8, 12),
                mid("chest_supported_dumbbell_row", 3, 10, 12),
                iso("bodyweight_glute_bridge", 2, 12, 20),
                iso("dumbbell_overhead_tricep_extension", 2, 10, 12),
                iso("dead_bug", 2, 8, 12),
            )),
        ),
    ),
    BuiltinTemplate(
        "two_day_full_body", "Two-day full body", "两天全身", "beginner", 2,
        (
            Day("a", "Day A", "A 日", (
                Item("back_squat", 3, 6, 10),
                mid("dumbbell_bench_press", 3, 8, 12),
                mid("lat_pulldown", 3, 8, 12),
                Item("romanian_deadlift", 2, 8, 10),
                iso("lateral_raise", 2, 12, 15),
                iso("dumbbell_curl", 2, 10, 12),
            )),
            Day("b", "Day B", "B 日", (
                Item("trap_bar_deadlift", 3, 5, 8),
                mid("leg_press", 2, 10, 12),
                mid("incline_dumbbell_bench_press", 3, 8, 12),
                mid("seated_cable_row", 3, 8, 12),
                mid("dumbbell_shoulder_press", 2, 8, 12),
                iso("tricep_pushdown", 2, 10, 15),
            )),
        ),
    ),
    BuiltinTemplate(
        "upper_lower_starter", "Upper / lower starter", "上下肢入门", "beginner", 4,
        (
            Day("upper_a", "Upper A", "上肢 A", (
                Item("barbell_bench_press", 3, 6, 10),
                mid("lat_pulldown", 3, 8, 12),
                mid("dumbbell_shoulder_press", 2, 8, 12),
                mid("seated_cable_row", 2, 8, 12),
                iso("dumbbell_curl", 2, 10, 12),
                iso("tricep_pushdown", 2, 10, 12),
            )),
            Day("lower_a", "Lower A", "下肢 A", (
                Item("back_squat", 3, 6, 10),
                Item("romanian_deadlift", 3, 8, 10),
                iso("leg_extension", 2, 10, 15),
                iso("seated_leg_curl", 2, 10, 15),
                iso("standing_calf_raise", 2, 10, 15),
            )),
            Day("upper_b", "Upper B", "上肢 B", (
                mid("incline_dumbbell_bench_press", 3, 8, 12),
                mid("machine_row", 3, 8, 12),
                mid("assisted_pull_up", 3, 6, 10),
                iso("lateral_raise", 3, 12, 15),
                iso("face_pull", 2, 12, 15),
                iso("hammer_curl", 2, 10, 12),
            )),
            Day("lower_b", "Lower B", "下肢 B", (
                Item("deadlift", 2, 5, 6),
                mid("leg_press", 3, 10, 12),
                mid("walking_lunge", 2, 8, 12),
                iso("lying_leg_curl", 2, 10, 15),
                iso("hanging_knee_raise", 2, 10, 15),
            )),
        ),
    ),
    # Intermediate: progress by the week, a heavy and a lighter day per lift.
    BuiltinTemplate(
        "upper_lower", "Upper / lower: strength and size", "上下肢：力量与增肌", "intermediate", 4,
        (
            Day("upper_heavy", "Upper heavy", "上肢大重量", (
                Item("barbell_bench_press", 4, 4, 6),
                Item("barbell_row", 4, 5, 8),
                Item("overhead_press", 3, 6, 8),
                mid("lat_pulldown", 3, 8, 10),
                iso("ez_bar_curl", 2, 8, 12),
                iso("skull_crusher", 2, 8, 12),
            )),
            Day("lower_heavy", "Lower heavy", "下肢大重量", (
                Item("back_squat", 4, 4, 6),
                Item("deadlift", 3, 3, 5),
                mid("leg_press", 3, 10, 12),
                iso("lying_leg_curl", 3, 8, 12),
                iso("standing_calf_raise", 3, 8, 12),
            )),
            Day("upper_moderate", "Upper volume", "上肢容量", (
                mid("incline_dumbbell_bench_press", 3, 8, 12),
                mid("pull_up", 3, 6, 10),
                mid("seated_cable_row", 3, 10, 12),
                iso("cable_fly", 2, 12, 15),
                iso("lateral_raise", 3, 12, 20),
                iso("incline_dumbbell_curl", 2, 10, 15),
                iso("overhead_cable_tricep_extension", 2, 10, 15),
            )),
            Day("lower_moderate", "Lower volume", "下肢容量", (
                Item("front_squat", 3, 8, 10),
                Item("romanian_deadlift", 3, 8, 10),
                mid("bulgarian_split_squat", 2, 10, 12),
                iso("leg_extension", 3, 12, 15),
                iso("seated_leg_curl", 3, 10, 15),
                iso("seated_calf_raise", 3, 12, 15),
            )),
        ),
    ),
    BuiltinTemplate(
        "heavy_light_volume", "Heavy, light, volume", "重日、轻日、容量日", "intermediate", 3,
        (
            Day("volume", "Volume", "容量日", (
                Item("back_squat", 5, 5, 5),
                Item("barbell_bench_press", 5, 5, 5),
                Item("barbell_row", 4, 6, 8),
                iso("face_pull", 2, 12, 15),
                iso("tricep_pushdown", 2, 10, 12),
            )),
            Day("light", "Light", "轻日", (
                Item("front_squat", 3, 4, 6),
                Item("overhead_press", 4, 5, 8),
                mid("chin_up", 3, 5, 8),
                Item("romanian_deadlift", 3, 6, 8),
                iso("hanging_leg_raise", 2, 10, 15),
            )),
            Day("heavy", "Heavy", "重日", (
                Item("back_squat", 3, 3, 5),
                Item("barbell_bench_press", 3, 3, 5),
                Item("deadlift", 2, 3, 5),
                mid("lat_pulldown", 3, 8, 10),
                iso("dumbbell_curl", 2, 10, 12),
            )),
        ),
    ),
    BuiltinTemplate(
        "strength_upper_lower", "Tiered strength", "分层力量", "intermediate", 4,
        (
            Day("day_1", "Day 1", "第 1 天", (
                Item("back_squat", 5, 3, 3),
                Item("barbell_bench_press", 3, 8, 10),
                iso("lat_pulldown", 3, 12, 15),
                iso("lateral_raise", 2, 15, 20),
            )),
            Day("day_2", "Day 2", "第 2 天", (
                Item("overhead_press", 5, 3, 3),
                Item("deadlift", 3, 8, 10),
                iso("dumbbell_row", 3, 12, 15),
                iso("dumbbell_curl", 2, 12, 15),
            )),
            Day("day_3", "Day 3", "第 3 天", (
                Item("barbell_bench_press", 5, 3, 3),
                Item("back_squat", 3, 8, 10),
                iso("lat_pulldown", 3, 12, 15),
                iso("tricep_pushdown", 2, 12, 15),
            )),
            Day("day_4", "Day 4", "第 4 天", (
                Item("deadlift", 5, 3, 3),
                Item("overhead_press", 3, 8, 10),
                iso("dumbbell_row", 3, 12, 15),
                iso("face_pull", 2, 15, 20),
            )),
        ),
    ),
    BuiltinTemplate(
        "upper_lower_ppl", "Upper / lower + push / pull / legs", "上下肢 + 推拉腿", "intermediate", 5,
        (
            Day("upper", "Upper", "上肢", (
                Item("barbell_bench_press", 3, 5, 8),
                mid("pull_up", 3, 6, 10),
                mid("seated_cable_row", 3, 8, 12),
                iso("lateral_raise", 2, 12, 20),
                iso("ez_bar_curl", 2, 8, 12),
                iso("overhead_cable_tricep_extension", 2, 10, 15),
            )),
            Day("lower", "Lower", "下肢", (
                Item("back_squat", 3, 5, 8),
                Item("romanian_deadlift", 3, 6, 10),
                mid("leg_press", 2, 10, 12),
                iso("seated_leg_curl", 3, 10, 15),
                iso("standing_calf_raise", 3, 10, 15),
            )),
            Day("push", "Push", "推", (
                mid("incline_dumbbell_bench_press", 3, 8, 12),
                mid("machine_shoulder_press", 2, 8, 12),
                iso("cable_fly", 3, 12, 15),
                iso("cable_lateral_raise", 3, 12, 20),
                iso("tricep_pushdown", 3, 10, 15),
            )),
            Day("pull", "Pull", "拉", (
                mid("lat_pulldown", 3, 8, 12),
                mid("chest_supported_dumbbell_row", 3, 8, 12),
                iso("reverse_pec_deck", 3, 12, 20),
                iso("bayesian_curl", 3, 10, 15),
                iso("hammer_curl", 2, 10, 12),
            )),
            Day("legs", "Legs", "腿", (
                mid("hack_squat", 3, 8, 12),
                mid("bulgarian_split_squat", 2, 8, 12),
                iso("lying_leg_curl", 3, 10, 15),
                iso("leg_extension", 3, 12, 15),
                iso("seated_calf_raise", 3, 12, 20),
                iso("cable_crunch", 3, 10, 15),
            )),
        ),
    ),
    BuiltinTemplate(
        "superset_full_body", "45-minute supersets", "45 分钟超级组", "intermediate", 3,
        (
            # Each pair shares a superset group: no rest after the first, then the pair's rest.
            Day("a", "Day A", "A 日", (
                pair(1, Item("back_squat", 3, 6, 10)), mid("lat_pulldown", 3, 8, 12, group=1),
                pair(2, mid("dumbbell_bench_press", 3, 8, 12)), mid("seated_cable_row", 3, 8, 12, group=2),
                pair(3, iso("lateral_raise", 2, 12, 20)), iso("hammer_curl", 2, 10, 15, rest=SHORT_REST, group=3),
            )),
            Day("b", "Day B", "B 日", (
                pair(1, Item("romanian_deadlift", 3, 8, 10)), mid("dumbbell_shoulder_press", 3, 8, 12, group=1),
                pair(2, mid("pull_up", 3, 6, 10)), mid("incline_dumbbell_bench_press", 3, 8, 12, group=2),
                pair(3, iso("leg_extension", 2, 12, 15)), iso("tricep_pushdown", 2, 10, 15, rest=SHORT_REST, group=3),
            )),
            Day("c", "Day C", "C 日", (
                pair(1, mid("leg_press", 3, 10, 12)), mid("machine_chest_press", 3, 8, 12, group=1),
                pair(2, mid("chest_supported_dumbbell_row", 3, 8, 12)), iso("seated_leg_curl", 3, 10, 15, group=2),
                pair(3, iso("cable_curl", 2, 10, 15)), iso("overhead_cable_tricep_extension", 2, 10, 15, rest=SHORT_REST, group=3),
            )),
        ),
    ),
    # Advanced: more volume, blocks that build up to a peak, and specialization.
    BuiltinTemplate(
        "push_pull_legs", "Push / pull / legs ×2", "推拉腿 ×2", "advanced", 6,
        (
            Day("push", "Push A", "推 A", (
                Item("barbell_bench_press", 4, 5, 8),
                Item("overhead_press", 3, 6, 10),
                mid("incline_dumbbell_bench_press", 3, 8, 12),
                iso("cable_lateral_raise", 3, 12, 20),
                iso("tricep_pushdown", 3, 10, 15),
            )),
            Day("pull", "Pull A", "拉 A", (
                Item("barbell_row", 4, 6, 10),
                mid("pull_up", 3, 6, 10),
                mid("seated_cable_row", 3, 10, 12),
                iso("face_pull", 3, 12, 20),
                iso("barbell_curl", 3, 8, 12),
                iso("hammer_curl", 2, 10, 15),
            )),
            Day("legs", "Legs A", "腿 A", (
                Item("back_squat", 4, 5, 8),
                Item("romanian_deadlift", 3, 8, 10),
                mid("leg_press", 3, 10, 15),
                iso("lying_leg_curl", 3, 10, 15),
                iso("standing_calf_raise", 4, 10, 15),
                iso("hanging_leg_raise", 3, 10, 15),
            )),
            Day("push_b", "Push B", "推 B", (
                mid("dumbbell_shoulder_press", 3, 8, 12),
                mid("machine_chest_press", 3, 10, 12),
                mid("chest_dip", 3, 8, 12),
                iso("cable_fly", 3, 12, 15),
                iso("lateral_raise", 4, 12, 20),
                iso("overhead_cable_tricep_extension", 3, 10, 15),
            )),
            Day("pull_b", "Pull B", "拉 B", (
                mid("lat_pulldown", 3, 10, 12),
                mid("chest_supported_dumbbell_row", 3, 8, 12),
                iso("straight_arm_pulldown", 2, 12, 15),
                iso("reverse_pec_deck", 3, 12, 20),
                iso("incline_dumbbell_curl", 3, 10, 15),
            )),
            Day("legs_b", "Legs B", "腿 B", (
                mid("hack_squat", 3, 8, 12),
                Item("hip_thrust", 3, 8, 12),
                iso("seated_leg_curl", 3, 10, 15),
                iso("leg_extension", 3, 12, 15),
                iso("seated_calf_raise", 4, 12, 20),
                iso("cable_crunch", 3, 10, 15),
            )),
        ),
    ),
    BuiltinTemplate(
        "powerbuilding", "Powerbuilding", "力量增肌", "advanced", 5,
        (
            Day("upper_power", "Upper power", "上肢力量", (
                Item("barbell_bench_press", 4, 3, 5),
                Item("pendlay_row", 4, 3, 5),
                Item("overhead_press", 3, 5, 8),
                mid("pull_up", 3, 5, 8),
                iso("barbell_curl", 2, 6, 10),
                iso("skull_crusher", 2, 6, 10),
            )),
            Day("lower_power", "Lower power", "下肢力量", (
                Item("back_squat", 4, 3, 5),
                Item("deadlift", 3, 3, 5),
                mid("leg_press", 3, 8, 10),
                iso("lying_leg_curl", 3, 6, 10),
                iso("standing_calf_raise", 3, 6, 10),
            )),
            Day("back_shoulders", "Back and shoulders", "背和肩", (
                Item("t_bar_row", 3, 8, 12),
                mid("lat_pulldown", 3, 10, 12),
                mid("single_arm_cable_row", 3, 10, 15),
                mid("dumbbell_shoulder_press", 3, 8, 12),
                iso("cable_lateral_raise", 3, 12, 20),
                iso("reverse_pec_deck", 3, 12, 20),
            )),
            Day("legs", "Legs", "腿", (
                mid("hack_squat", 4, 8, 12),
                Item("romanian_deadlift", 3, 8, 12),
                mid("walking_lunge", 3, 10, 12),
                iso("leg_extension", 3, 12, 15),
                iso("seated_leg_curl", 3, 10, 15),
                iso("seated_calf_raise", 4, 12, 20),
            )),
            Day("chest_arms", "Chest and arms", "胸和手臂", (
                mid("incline_dumbbell_bench_press", 3, 8, 12),
                mid("machine_chest_press", 3, 10, 12),
                iso("cable_fly", 3, 12, 15),
                iso("incline_dumbbell_curl", 3, 10, 15),
                iso("overhead_cable_tricep_extension", 3, 10, 15),
                iso("hammer_curl", 2, 10, 12),
            )),
        ),
    ),
    BuiltinTemplate(
        "strength_block_build", "Strength block 1: build", "力量周期 1：积累", "advanced", 4,
        (
            Day("day_1", "Day 1", "第 1 天", (
                Item("back_squat", 5, 4, 6),
                Item("barbell_bench_press", 5, 4, 6),
                Item("romanian_deadlift", 3, 6, 8),
                mid("lat_pulldown", 3, 8, 12),
                iso("ab_wheel_rollout", 3, 8, 12),
            )),
            Day("day_2", "Day 2", "第 2 天", (
                Item("deficit_deadlift", 4, 3, 5),
                Item("overhead_press", 3, 6, 8),
                Item("barbell_row", 4, 6, 8),
                iso("lying_leg_curl", 3, 8, 12),
                iso("back_extension", 2, 10, 15),
            )),
            Day("day_3", "Day 3", "第 3 天", (
                Item("pause_squat", 4, 4, 6),
                Item("close_grip_bench_press", 4, 6, 8),
                mid("chin_up", 3, 6, 10),
                iso("face_pull", 3, 12, 15),
                iso("hanging_leg_raise", 3, 8, 12),
            )),
            Day("day_4", "Day 4", "第 4 天", (
                Item("paused_bench_press", 4, 4, 6),
                Item("good_morning", 3, 6, 8),
                mid("dumbbell_row", 3, 8, 12),
                iso("skull_crusher", 3, 8, 12),
                iso("hammer_curl", 2, 10, 12),
            )),
        ),
    ),
    BuiltinTemplate(
        "strength_block_peak", "Strength block 2: peak", "力量周期 2：冲刺", "advanced", 4,
        (
            Day("day_1", "Day 1", "第 1 天", (
                Item("back_squat", 4, 2, 3, PEAK_REST),
                Item("barbell_bench_press", 4, 2, 3, PEAK_REST),
                Item("romanian_deadlift", 2, 5, 6),
                mid("lat_pulldown", 2, 8, 10),
            )),
            Day("day_2", "Day 2", "第 2 天", (
                Item("deadlift", 3, 1, 3, PEAK_REST),
                Item("overhead_press", 2, 5, 6),
                Item("barbell_row", 3, 5, 6),
                iso("hanging_leg_raise", 2, 8, 12),
            )),
            Day("day_3", "Day 3", "第 3 天", (
                Item("pause_squat", 3, 3, 4),
                Item("paused_bench_press", 3, 3, 4),
                mid("chin_up", 2, 5, 8),
                iso("tricep_pushdown", 2, 8, 12),
            )),
            Day("day_4", "Day 4", "第 4 天", (
                Item("barbell_bench_press", 2, 1, 2, PEAK_REST),
                Item("pin_press", 2, 3, 5),
                mid("dumbbell_row", 2, 8, 10),
                iso("face_pull", 2, 12, 15),
            )),
        ),
    ),
    BuiltinTemplate(
        "upper_body_focus", "Upper-body focus", "上肢专项", "advanced", 5,
        (
            Day("chest", "Chest", "胸", (
                Item("barbell_bench_press", 4, 5, 8),
                mid("incline_dumbbell_bench_press", 3, 8, 12),
                mid("lat_pulldown", 3, 8, 12),
                iso("cable_fly", 3, 12, 15),
                iso("lateral_raise", 3, 12, 20),
                iso("tricep_pushdown", 3, 10, 15),
            )),
            Day("back", "Back", "背", (
                Item("barbell_row", 4, 6, 10),
                mid("pull_up", 3, 6, 10),
                mid("chest_supported_dumbbell_row", 3, 8, 12),
                mid("machine_chest_press", 2, 10, 12),
                iso("reverse_pec_deck", 3, 12, 20),
                iso("barbell_curl", 3, 8, 12),
            )),
            Day("legs", "Legs", "腿", (
                Item("back_squat", 3, 5, 8),
                Item("romanian_deadlift", 3, 6, 10),
                iso("leg_extension", 2, 12, 15),
                iso("lying_leg_curl", 2, 10, 15),
                iso("standing_calf_raise", 3, 10, 15),
            )),
            Day("shoulders_arms", "Shoulders and arms", "肩和手臂", (
                Item("overhead_press", 3, 6, 10),
                iso("cable_lateral_raise", 4, 12, 20),
                iso("face_pull", 3, 12, 20),
                iso("incline_dumbbell_curl", 3, 10, 15),
                iso("overhead_cable_tricep_extension", 3, 10, 15),
                iso("hammer_curl", 2, 10, 12),
            )),
            Day("pump", "Pump", "泵感", (
                mid("incline_machine_chest_press", 3, 10, 12),
                mid("single_arm_lat_pulldown", 3, 10, 15),
                mid("seated_cable_row", 3, 10, 12),
                iso("pec_deck", 3, 12, 15),
                iso("machine_lateral_raise", 3, 12, 20),
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
                        superset_group=item.superset,
                        sets=[
                            TemplateSetWrite(
                                id=_id(entry.slug, day.slug, position, number),
                                rep_min=item.rep_min,
                                rep_max=item.rep_max,
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
