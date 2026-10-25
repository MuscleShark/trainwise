"""Built-in exercise catalog.

This list is the source of truth. `sync_builtin_exercises` writes it to the database
after migrations on every deploy (see migrate_handler.py): new entries are added,
changed ones updated, and removed ones soft-deleted so old workouts keep their
reference. IDs are derived from the slug, so never rename a slug.

Written for IronSage (not copied from another exercise database).

Run by hand with: python catalog.py
"""

import uuid
from typing import NamedTuple

from sqlalchemy import select
from sqlalchemy.orm import Session

from models import Exercise, utcnow

CATALOG_NAMESPACE = uuid.UUID("6f1c2a52-3b7e-4f0a-9a51-1d8e4c7b2f10")

MUSCLES = (
    "chest",
    "upper_back",
    "lats",
    "traps",
    "front_delts",
    "side_delts",
    "rear_delts",
    "biceps",
    "triceps",
    "forearms",
    "abs",
    "obliques",
    "lower_back",
    "glutes",
    "quads",
    "hamstrings",
    "adductors",
    "abductors",
    "calves",
)
EQUIPMENT = (
    "barbell",
    "dumbbell",
    "machine",
    "cable",
    "smith",
    "bodyweight",
    "kettlebell",
    "band",
    "other",
)
LOAD_TYPES = ("total", "per_side", "bodyweight_plus", "assisted")


class CatalogExercise(NamedTuple):
    slug: str
    name_en: str
    name_zh: str
    equipment: str
    load_type: str
    primary: tuple[str, ...]
    secondary: tuple[str, ...] = ()


E = CatalogExercise

BUILTIN_EXERCISES: tuple[CatalogExercise, ...] = (
    # Chest
    E("barbell_bench_press", "Barbell bench press", "杠铃卧推", "barbell", "total", ("chest",), ("front_delts", "triceps")),
    E("incline_barbell_bench_press", "Incline barbell bench press", "上斜杠铃卧推", "barbell", "total", ("chest",), ("front_delts", "triceps")),
    E("decline_barbell_bench_press", "Decline barbell bench press", "下斜杠铃卧推", "barbell", "total", ("chest",), ("triceps",)),
    E("close_grip_bench_press", "Close-grip bench press", "窄距卧推", "barbell", "total", ("triceps",), ("chest", "front_delts")),
    E("floor_press", "Floor press", "地板卧推", "barbell", "total", ("chest", "triceps"), ("front_delts",)),
    E("dumbbell_bench_press", "Dumbbell bench press", "哑铃卧推", "dumbbell", "per_side", ("chest",), ("front_delts", "triceps")),
    E("incline_dumbbell_bench_press", "Incline dumbbell bench press", "上斜哑铃卧推", "dumbbell", "per_side", ("chest",), ("front_delts", "triceps")),
    E("decline_dumbbell_bench_press", "Decline dumbbell bench press", "下斜哑铃卧推", "dumbbell", "per_side", ("chest",), ("triceps",)),
    E("dumbbell_fly", "Dumbbell fly", "哑铃飞鸟", "dumbbell", "per_side", ("chest",), ("front_delts",)),
    E("incline_dumbbell_fly", "Incline dumbbell fly", "上斜哑铃飞鸟", "dumbbell", "per_side", ("chest",), ("front_delts",)),
    E("machine_chest_press", "Machine chest press", "器械推胸", "machine", "total", ("chest",), ("front_delts", "triceps")),
    E("incline_machine_chest_press", "Incline machine chest press", "上斜器械推胸", "machine", "total", ("chest",), ("front_delts", "triceps")),
    E("iso_lateral_chest_press", "Iso-lateral chest press", "分动式推胸机", "machine", "per_side", ("chest",), ("front_delts", "triceps")),
    E("pec_deck", "Pec deck", "蝴蝶机夹胸", "machine", "total", ("chest",), ("front_delts",)),
    E("cable_fly", "Cable fly", "龙门架夹胸", "cable", "per_side", ("chest",), ("front_delts",)),
    E("low_to_high_cable_fly", "Low-to-high cable fly", "低位龙门架夹胸", "cable", "per_side", ("chest",), ("front_delts",)),
    E("smith_bench_press", "Smith machine bench press", "史密斯卧推", "smith", "total", ("chest",), ("front_delts", "triceps")),
    E("smith_incline_bench_press", "Smith machine incline bench press", "史密斯上斜卧推", "smith", "total", ("chest",), ("front_delts", "triceps")),
    E("push_up", "Push-up", "俯卧撑", "bodyweight", "bodyweight_plus", ("chest",), ("front_delts", "triceps")),
    E("chest_dip", "Chest dip", "双杠臂屈伸（练胸）", "bodyweight", "bodyweight_plus", ("chest",), ("triceps", "front_delts")),
    # Back
    E("deadlift", "Deadlift", "硬拉", "barbell", "total", ("hamstrings", "glutes", "lower_back"), ("quads", "traps", "forearms")),
    E("sumo_deadlift", "Sumo deadlift", "相扑硬拉", "barbell", "total", ("glutes", "quads", "adductors"), ("hamstrings", "lower_back", "traps")),
    E("trap_bar_deadlift", "Trap bar deadlift", "六角杠硬拉", "barbell", "total", ("quads", "glutes"), ("hamstrings", "traps", "lower_back")),
    E("romanian_deadlift", "Romanian deadlift", "罗马尼亚硬拉", "barbell", "total", ("hamstrings", "glutes"), ("lower_back",)),
    E("stiff_leg_deadlift", "Stiff-leg deadlift", "直腿硬拉", "barbell", "total", ("hamstrings",), ("glutes", "lower_back")),
    E("rack_pull", "Rack pull", "架上拉", "barbell", "total", ("traps", "lower_back", "glutes"), ("hamstrings", "forearms")),
    E("good_morning", "Good morning", "早安式体前屈", "barbell", "total", ("hamstrings", "lower_back"), ("glutes",)),
    E("barbell_row", "Barbell row", "杠铃划船", "barbell", "total", ("upper_back", "lats"), ("biceps", "rear_delts")),
    E("pendlay_row", "Pendlay row", "彭德雷划船", "barbell", "total", ("upper_back", "lats"), ("biceps", "rear_delts")),
    E("seal_row", "Seal row", "海豹划船", "barbell", "total", ("upper_back", "lats"), ("biceps", "rear_delts")),
    E("t_bar_row", "T-bar row", "T 杠划船", "barbell", "total", ("upper_back", "lats"), ("biceps", "rear_delts")),
    E("meadows_row", "Meadows row", "米多斯划船", "barbell", "total", ("lats", "upper_back"), ("biceps", "rear_delts")),
    E("dumbbell_row", "One-arm dumbbell row", "单臂哑铃划船", "dumbbell", "per_side", ("lats", "upper_back"), ("biceps", "rear_delts")),
    E("chest_supported_dumbbell_row", "Chest-supported dumbbell row", "俯卧哑铃划船", "dumbbell", "per_side", ("upper_back", "lats"), ("biceps", "rear_delts")),
    E("seated_cable_row", "Seated cable row", "坐姿绳索划船", "cable", "total", ("upper_back", "lats"), ("biceps", "rear_delts")),
    E("single_arm_cable_row", "Single-arm cable row", "单臂绳索划船", "cable", "per_side", ("lats", "upper_back"), ("biceps",)),
    E("machine_row", "Machine row", "器械划船", "machine", "total", ("upper_back", "lats"), ("biceps", "rear_delts")),
    E("iso_lateral_row", "Iso-lateral row", "分动式划船机", "machine", "per_side", ("upper_back", "lats"), ("biceps", "rear_delts")),
    E("lat_pulldown", "Lat pulldown", "高位下拉", "cable", "total", ("lats",), ("biceps", "upper_back")),
    E("close_grip_lat_pulldown", "Close-grip lat pulldown", "窄握高位下拉", "cable", "total", ("lats",), ("biceps", "upper_back")),
    E("single_arm_lat_pulldown", "Single-arm lat pulldown", "单臂高位下拉", "cable", "per_side", ("lats",), ("biceps",)),
    E("iso_lateral_high_row", "Iso-lateral high row", "分动式高位下拉机", "machine", "per_side", ("lats", "upper_back"), ("biceps",)),
    E("straight_arm_pulldown", "Straight-arm pulldown", "直臂下拉", "cable", "total", ("lats",), ("triceps",)),
    E("dumbbell_pullover", "Dumbbell pullover", "哑铃仰卧上拉", "dumbbell", "total", ("lats",), ("chest", "triceps")),
    E("pull_up", "Pull-up", "引体向上", "bodyweight", "bodyweight_plus", ("lats",), ("biceps", "upper_back")),
    E("chin_up", "Chin-up", "反手引体向上", "bodyweight", "bodyweight_plus", ("lats", "biceps"), ("upper_back",)),
    E("assisted_pull_up", "Assisted pull-up", "辅助引体向上", "machine", "assisted", ("lats",), ("biceps", "upper_back")),
    E("inverted_row", "Inverted row", "反向划船", "bodyweight", "bodyweight_plus", ("upper_back", "lats"), ("biceps", "rear_delts")),
    E("back_extension", "Back extension", "山羊挺身", "bodyweight", "bodyweight_plus", ("lower_back", "glutes"), ("hamstrings",)),
    E("reverse_hyperextension", "Reverse hyperextension", "反向山羊挺身", "machine", "total", ("glutes", "lower_back"), ("hamstrings",)),
    E("barbell_shrug", "Barbell shrug", "杠铃耸肩", "barbell", "total", ("traps",), ("forearms",)),
    E("dumbbell_shrug", "Dumbbell shrug", "哑铃耸肩", "dumbbell", "per_side", ("traps",), ("forearms",)),
    E("face_pull", "Face pull", "面拉", "cable", "total", ("rear_delts",), ("upper_back", "traps")),
    # Shoulders
    E("overhead_press", "Overhead press", "站姿杠铃推举", "barbell", "total", ("front_delts",), ("triceps", "side_delts")),
    E("seated_barbell_press", "Seated barbell press", "坐姿杠铃推举", "barbell", "total", ("front_delts",), ("triceps", "side_delts")),
    E("push_press", "Push press", "借力推举", "barbell", "total", ("front_delts",), ("triceps", "quads")),
    E("landmine_press", "Landmine press", "地雷管推举", "barbell", "total", ("front_delts",), ("chest", "triceps")),
    E("dumbbell_shoulder_press", "Dumbbell shoulder press", "哑铃肩推", "dumbbell", "per_side", ("front_delts",), ("triceps", "side_delts")),
    E("arnold_press", "Arnold press", "阿诺德推举", "dumbbell", "per_side", ("front_delts",), ("side_delts", "triceps")),
    E("machine_shoulder_press", "Machine shoulder press", "器械肩推", "machine", "total", ("front_delts",), ("triceps", "side_delts")),
    E("iso_lateral_shoulder_press", "Iso-lateral shoulder press", "分动式肩推机", "machine", "per_side", ("front_delts",), ("triceps", "side_delts")),
    E("smith_shoulder_press", "Smith machine shoulder press", "史密斯肩推", "smith", "total", ("front_delts",), ("triceps", "side_delts")),
    E("lateral_raise", "Dumbbell lateral raise", "哑铃侧平举", "dumbbell", "per_side", ("side_delts",), ("traps",)),
    E("cable_lateral_raise", "Cable lateral raise", "绳索侧平举", "cable", "per_side", ("side_delts",)),
    E("machine_lateral_raise", "Machine lateral raise", "器械侧平举", "machine", "total", ("side_delts",)),
    E("front_raise", "Dumbbell front raise", "哑铃前平举", "dumbbell", "per_side", ("front_delts",)),
    E("rear_delt_fly", "Bent-over dumbbell rear delt fly", "俯身哑铃飞鸟", "dumbbell", "per_side", ("rear_delts",), ("upper_back",)),
    E("reverse_pec_deck", "Reverse pec deck", "反向蝴蝶机", "machine", "total", ("rear_delts",), ("upper_back",)),
    E("cable_rear_delt_fly", "Cable rear delt fly", "绳索反向飞鸟", "cable", "per_side", ("rear_delts",), ("upper_back",)),
    E("upright_row", "Barbell upright row", "杠铃直立划船", "barbell", "total", ("side_delts", "traps"), ("biceps",)),
    # Biceps and forearms
    E("barbell_curl", "Barbell curl", "杠铃弯举", "barbell", "total", ("biceps",), ("forearms",)),
    E("ez_bar_curl", "EZ-bar curl", "曲杠弯举", "barbell", "total", ("biceps",), ("forearms",)),
    E("dumbbell_curl", "Dumbbell curl", "哑铃弯举", "dumbbell", "per_side", ("biceps",), ("forearms",)),
    E("hammer_curl", "Hammer curl", "锤式弯举", "dumbbell", "per_side", ("biceps", "forearms")),
    E("incline_dumbbell_curl", "Incline dumbbell curl", "上斜哑铃弯举", "dumbbell", "per_side", ("biceps",)),
    E("concentration_curl", "Concentration curl", "集中弯举", "dumbbell", "per_side", ("biceps",)),
    E("preacher_curl", "Preacher curl", "牧师凳弯举", "barbell", "total", ("biceps",)),
    E("machine_preacher_curl", "Machine preacher curl", "器械牧师凳弯举", "machine", "total", ("biceps",)),
    E("cable_curl", "Cable curl", "绳索弯举", "cable", "total", ("biceps",), ("forearms",)),
    E("bayesian_curl", "Bayesian cable curl", "贝叶斯绳索弯举", "cable", "per_side", ("biceps",)),
    E("rope_hammer_curl", "Rope hammer curl", "绳索锤式弯举", "cable", "total", ("biceps", "forearms")),
    E("reverse_curl", "Reverse curl", "反握弯举", "barbell", "total", ("forearms",), ("biceps",)),
    E("wrist_curl", "Wrist curl", "腕弯举", "dumbbell", "per_side", ("forearms",)),
    # Triceps
    E("tricep_pushdown", "Triceps pushdown", "绳索下压", "cable", "total", ("triceps",)),
    E("overhead_cable_tricep_extension", "Overhead cable triceps extension", "绳索过头臂屈伸", "cable", "total", ("triceps",)),
    E("dumbbell_overhead_tricep_extension", "Dumbbell overhead triceps extension", "哑铃颈后臂屈伸", "dumbbell", "total", ("triceps",)),
    E("skull_crusher", "Skull crusher", "仰卧臂屈伸", "barbell", "total", ("triceps",)),
    E("dumbbell_skull_crusher", "Dumbbell skull crusher", "哑铃仰卧臂屈伸", "dumbbell", "per_side", ("triceps",)),
    E("machine_tricep_extension", "Machine triceps extension", "器械臂屈伸", "machine", "total", ("triceps",)),
    E("dumbbell_kickback", "Dumbbell kickback", "哑铃臂屈伸后踢", "dumbbell", "per_side", ("triceps",)),
    E("tricep_dip", "Triceps dip", "双杠臂屈伸（练三头）", "bodyweight", "bodyweight_plus", ("triceps",), ("chest", "front_delts")),
    E("bench_dip", "Bench dip", "凳上臂屈伸", "bodyweight", "bodyweight_plus", ("triceps",), ("front_delts",)),
    # Quads, glutes and hamstrings
    E("back_squat", "Back squat", "杠铃深蹲", "barbell", "total", ("quads", "glutes"), ("adductors", "lower_back")),
    E("front_squat", "Front squat", "杠铃前蹲", "barbell", "total", ("quads",), ("glutes", "upper_back")),
    E("box_squat", "Box squat", "箱式深蹲", "barbell", "total", ("quads", "glutes"), ("hamstrings",)),
    E("safety_bar_squat", "Safety bar squat", "安全杠深蹲", "barbell", "total", ("quads", "glutes"), ("upper_back",)),
    E("goblet_squat", "Goblet squat", "高脚杯深蹲", "dumbbell", "total", ("quads", "glutes")),
    E("smith_squat", "Smith machine squat", "史密斯深蹲", "smith", "total", ("quads", "glutes")),
    E("hack_squat", "Hack squat", "哈克深蹲", "machine", "total", ("quads",), ("glutes",)),
    E("pendulum_squat", "Pendulum squat", "钟摆深蹲", "machine", "total", ("quads",), ("glutes",)),
    E("belt_squat", "Belt squat", "腰带深蹲", "machine", "total", ("quads", "glutes")),
    E("leg_press", "Leg press", "腿举", "machine", "total", ("quads", "glutes"), ("adductors",)),
    E("single_leg_press", "Single-leg press", "单腿腿举", "machine", "total", ("quads", "glutes")),
    E("bulgarian_split_squat", "Bulgarian split squat", "保加利亚分腿蹲", "dumbbell", "per_side", ("quads", "glutes"), ("adductors",)),
    E("walking_lunge", "Walking lunge", "哑铃箭步走", "dumbbell", "per_side", ("quads", "glutes"), ("adductors",)),
    E("reverse_lunge", "Reverse lunge", "后撤箭步蹲", "dumbbell", "per_side", ("quads", "glutes")),
    E("smith_lunge", "Smith machine lunge", "史密斯箭步蹲", "smith", "total", ("quads", "glutes")),
    E("step_up", "Step-up", "箱上登阶", "dumbbell", "per_side", ("quads", "glutes")),
    E("leg_extension", "Leg extension", "腿屈伸", "machine", "total", ("quads",)),
    E("lying_leg_curl", "Lying leg curl", "俯卧腿弯举", "machine", "total", ("hamstrings",)),
    E("seated_leg_curl", "Seated leg curl", "坐姿腿弯举", "machine", "total", ("hamstrings",)),
    E("nordic_curl", "Nordic curl", "北欧挺", "bodyweight", "bodyweight_plus", ("hamstrings",)),
    E("glute_ham_raise", "Glute-ham raise", "臀腿挺身", "bodyweight", "bodyweight_plus", ("hamstrings", "glutes")),
    E("dumbbell_romanian_deadlift", "Dumbbell Romanian deadlift", "哑铃罗马尼亚硬拉", "dumbbell", "per_side", ("hamstrings", "glutes"), ("lower_back",)),
    E("single_leg_romanian_deadlift", "Single-leg Romanian deadlift", "单腿罗马尼亚硬拉", "dumbbell", "per_side", ("hamstrings", "glutes")),
    E("hip_thrust", "Barbell hip thrust", "杠铃臀推", "barbell", "total", ("glutes",), ("hamstrings",)),
    E("machine_hip_thrust", "Machine hip thrust", "器械臀推", "machine", "total", ("glutes",), ("hamstrings",)),
    E("glute_bridge", "Barbell glute bridge", "杠铃臀桥", "barbell", "total", ("glutes",), ("hamstrings",)),
    E("cable_glute_kickback", "Cable glute kickback", "绳索后踢腿", "cable", "per_side", ("glutes",)),
    E("machine_glute_kickback", "Machine glute kickback", "器械后踢腿", "machine", "total", ("glutes",)),
    E("hip_abduction", "Hip abduction machine", "髋外展机", "machine", "total", ("abductors",), ("glutes",)),
    E("hip_adduction", "Hip adduction machine", "髋内收机", "machine", "total", ("adductors",)),
    E("kettlebell_swing", "Kettlebell swing", "壶铃摆荡", "kettlebell", "total", ("glutes", "hamstrings"), ("lower_back",)),
    E("sled_push", "Sled push", "推雪橇", "other", "total", ("quads", "glutes"), ("calves",)),
    # Calves
    E("standing_calf_raise", "Standing calf raise", "站姿提踵", "machine", "total", ("calves",)),
    E("seated_calf_raise", "Seated calf raise", "坐姿提踵", "machine", "total", ("calves",)),
    E("leg_press_calf_raise", "Leg press calf raise", "腿举机提踵", "machine", "total", ("calves",)),
    E("smith_calf_raise", "Smith machine calf raise", "史密斯提踵", "smith", "total", ("calves",)),
    # Core
    E("plank", "Plank", "平板支撑", "bodyweight", "bodyweight_plus", ("abs",), ("obliques",)),
    E("side_plank", "Side plank", "侧平板支撑", "bodyweight", "bodyweight_plus", ("obliques",), ("abs",)),
    E("hollow_hold", "Hollow hold", "空心支撑", "bodyweight", "bodyweight_plus", ("abs",)),
    E("dead_bug", "Dead bug", "死虫式", "bodyweight", "bodyweight_plus", ("abs",)),
    E("crunch", "Crunch", "卷腹", "bodyweight", "bodyweight_plus", ("abs",)),
    E("decline_sit_up", "Decline sit-up", "下斜仰卧起坐", "bodyweight", "bodyweight_plus", ("abs",)),
    E("leg_raise", "Lying leg raise", "仰卧举腿", "bodyweight", "bodyweight_plus", ("abs",)),
    E("hanging_leg_raise", "Hanging leg raise", "悬垂举腿", "bodyweight", "bodyweight_plus", ("abs",), ("forearms",)),
    E("hanging_knee_raise", "Hanging knee raise", "悬垂屈膝举腿", "bodyweight", "bodyweight_plus", ("abs",), ("forearms",)),
    E("ab_wheel_rollout", "Ab wheel rollout", "健腹轮", "other", "bodyweight_plus", ("abs",), ("lats",)),
    E("cable_crunch", "Cable crunch", "绳索卷腹", "cable", "total", ("abs",)),
    E("machine_crunch", "Machine crunch", "器械卷腹", "machine", "total", ("abs",)),
    E("russian_twist", "Russian twist", "俄罗斯转体", "bodyweight", "bodyweight_plus", ("obliques",), ("abs",)),
    E("pallof_press", "Pallof press", "绳索抗旋转推", "cable", "total", ("obliques", "abs")),
    # Full body
    E("power_clean", "Power clean", "高翻", "barbell", "total", ("quads", "glutes", "traps"), ("hamstrings", "upper_back")),
    E("hang_clean", "Hang clean", "悬垂翻", "barbell", "total", ("traps", "glutes"), ("quads", "hamstrings")),
    E("farmers_carry", "Farmer's carry", "农夫行走", "dumbbell", "per_side", ("forearms", "traps"), ("abs",)),
)  # fmt: skip


# Other names people search for: abbreviations, gym slang and common Chinese names.
# The app also matches pinyin and typos on its own, so these are only names it could
# not derive from name_en or name_zh.
ALIASES: dict[str, tuple[str, ...]] = {
    "barbell_bench_press": ("bench", "bench press", "BP", "卧推", "平板卧推"),
    "incline_barbell_bench_press": ("incline bench", "上斜卧推"),
    "close_grip_bench_press": ("CGBP", "窄卧"),
    "dumbbell_bench_press": ("DB bench", "DB press"),
    "incline_dumbbell_bench_press": ("incline DB press", "上斜哑铃推"),
    "dumbbell_fly": ("DB fly", "飞鸟"),
    "machine_chest_press": ("chest press", "坐姿推胸"),
    "pec_deck": ("pec fly", "machine fly", "夹胸", "蝴蝶机"),
    "cable_fly": ("cable crossover", "绳索夹胸"),
    "push_up": ("pushup", "press-up"),
    "chest_dip": ("dips", "双杠"),
    "deadlift": ("DL", "conventional deadlift", "传统硬拉"),
    "sumo_deadlift": ("sumo",),
    "trap_bar_deadlift": ("hex bar deadlift",),
    "romanian_deadlift": ("RDL", "罗马硬拉"),
    "stiff_leg_deadlift": ("SLDL",),
    "barbell_row": ("bent-over row", "BOR", "俯身划船", "俯身杠铃划船"),
    "t_bar_row": ("T杠划船",),
    "dumbbell_row": ("DB row", "单臂划船"),
    "seated_cable_row": ("cable row", "坐姿划船"),
    "lat_pulldown": ("pulldown", "下拉"),
    "pull_up": ("pullup", "引体"),
    "chin_up": ("chinup", "反手引体"),
    "back_extension": ("hyperextension", "背屈伸"),
    "face_pull": ("绳索面拉",),
    "overhead_press": ("OHP", "military press", "推举", "杠铃推举"),
    "dumbbell_shoulder_press": ("DB shoulder press", "哑铃推举"),
    "lateral_raise": ("side raise", "lat raise", "侧平举"),
    "rear_delt_fly": ("reverse fly", "反向飞鸟"),
    "reverse_pec_deck": ("rear delt machine", "反飞鸟"),
    "barbell_curl": ("curl", "弯举", "二头弯举"),
    "ez_bar_curl": ("EZ curl",),
    "skull_crusher": ("lying triceps extension", "LTE"),
    "tricep_pushdown": ("pushdown", "三头下压"),
    "tricep_dip": ("dips",),
    "back_squat": ("squat", "深蹲", "后蹲"),
    "front_squat": ("前蹲",),
    "goblet_squat": ("杯式深蹲",),
    "smith_squat": ("史密斯蹲",),
    "hack_squat": ("哈克",),
    "leg_press": ("倒蹬",),
    "bulgarian_split_squat": ("BSS", "保加利亚蹲", "分腿蹲"),
    "walking_lunge": ("lunge", "箭步蹲"),
    "leg_extension": ("quad extension", "腿伸展"),
    "lying_leg_curl": ("leg curl", "腿弯举"),
    "seated_leg_curl": ("leg curl",),
    "hip_thrust": ("臀推",),
    "glute_bridge": ("臀桥",),
    "hip_abduction": ("abductor machine", "外展"),
    "hip_adduction": ("adductor machine", "内收"),
    "standing_calf_raise": ("calf raise", "提踵"),
    "plank": ("平板",),
    "hanging_leg_raise": ("HLR",),
    "ab_wheel_rollout": ("ab roller", "腹轮"),
    "kettlebell_swing": ("KB swing",),
    "power_clean": ("clean",),
    "farmers_carry": ("farmer's walk", "农夫走"),
}


def exercise_id(slug: str) -> uuid.UUID:
    return uuid.uuid5(CATALOG_NAMESPACE, f"exercise:{slug}")


def sync_builtin_exercises(db: Session) -> dict[str, int]:
    """Makes the built-in rows in `exercises` match BUILTIN_EXERCISES."""
    existing = {
        row.id: row for row in db.scalars(select(Exercise).where(Exercise.owner_user_id.is_(None)))
    }
    counts = {"added": 0, "updated": 0, "removed": 0}

    for entry in BUILTIN_EXERCISES:
        values = {
            "name_en": entry.name_en,
            "name_zh": entry.name_zh,
            "equipment": entry.equipment,
            "load_type": entry.load_type,
            "primary_muscles": list(entry.primary),
            "secondary_muscles": list(entry.secondary),
            "aliases": list(ALIASES.get(entry.slug, ())),
            "deleted_at": None,
        }
        row = existing.pop(exercise_id(entry.slug), None)
        if row is None:
            db.add(Exercise(id=exercise_id(entry.slug), owner_user_id=None, **values))
            counts["added"] += 1
        elif any(getattr(row, key) != value for key, value in values.items()):
            for key, value in values.items():
                setattr(row, key, value)
            counts["updated"] += 1

    for row in existing.values():
        if row.deleted_at is None:
            row.deleted_at = utcnow()
            counts["removed"] += 1

    db.commit()
    return counts


if __name__ == "__main__":
    from database import SessionLocal

    with SessionLocal() as session:
        print(sync_builtin_exercises(session))
