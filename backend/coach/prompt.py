"""The instructions and input sent to the model.

Instructions live in Markdown "skills" under coach/skills/, loaded by the task they
belong to. They are plain text, so they work the same with every provider.
"""

import json
from decimal import ROUND_HALF_UP, Decimal
from functools import cache
from pathlib import Path

from pydantic import BaseModel

from .schemas import CoachInput, CoachOutput, WeeklyInput

SKILLS = Path(__file__).parent / "skills"

# Which skills each task loads, besides safety, which is always loaded.
TASKS = {"next_session": ["next_session"], "weekly_summary": ["weekly_summary"]}

# What each task is, said first, and what its answer must hold, said last.
ROLES = {
    "next_session": "You adjust a rule-based plan for the user's next session and explain "
    "it in a sentence.",
    "weekly_summary": "You write the user's weekly training summary from numbers the app "
    "has already computed.",
}
ANSWERS = {
    "next_session": "Answer with JSON matching the schema you were given: one entry per "
    "exercise in the input, with its exercise_id, an action and a reason.",
    "weekly_summary": "Answer with JSON matching the schema you were given: the summary, "
    "one or two suggestions, and whether one of them is a lighter week.",
}

LANGUAGES = {"en": "English", "zh": "Simplified Chinese"}


@cache
def skill(name: str) -> str:
    return (SKILLS / f"{name}.md").read_text(encoding="utf-8").strip()


def system_prompt(task: str = "next_session") -> str:
    """The same for every request of a task, so providers can cache it."""
    parts = [
        "You are the IronSage coach. IronSage is a strength-training log. " + ROLES[task],
        skill("safety"),
        *(skill(name) for name in TASKS[task]),
        ANSWERS[task],
    ]
    return "\n\n".join(parts)


KG_PER_LB = Decimal("0.45359237")


def weight_text(kg: float, unit: str) -> str:
    """A weight as the app shows it (WeightUnit.format in
    ios/IronSageKit/Sources/IronSageCore/Units.swift): kilograms to two decimals,
    pounds to one, halves rounded up, no trailing zeros. 140 kg is "140 kg" or "308.6 lb"."""
    value = Decimal(str(kg))
    if unit == "lb":
        value = (value / KG_PER_LB).quantize(Decimal("0.1"), ROUND_HALF_UP)
    else:
        value = value.quantize(Decimal("0.01"), ROUND_HALF_UP)
    text = format(value.normalize(), "f")
    return f"{text} {unit}"


def in_unit(node, unit: str):
    """Replaces every `…_kg` number with `…`, the weight as the app shows it, so the
    model quotes weights and never converts or rounds them."""
    if isinstance(node, dict):
        converted = {}
        for key, value in node.items():
            if key.endswith("_kg") and isinstance(value, int | float):
                converted[key.removesuffix("_kg")] = weight_text(value, unit)
            else:
                converted[key] = in_unit(value, unit)
        return converted
    if isinstance(node, list):
        return [in_unit(item, unit) for item in node]
    return node


def model_view(plan: CoachInput | WeeklyInput) -> dict:
    """The input as the model sees it: weights in the user's unit, and for the next
    session each planned weight change already worked out."""
    data = plan.model_dump(mode="json", exclude_none=True)
    if isinstance(plan, CoachInput):
        for exercise, view in zip(plan.exercises, data["exercises"]):
            top = max((s.weight_kg or 0 for s in exercise.planned_sets), default=0)
            if exercise.last_weight_kg and top and abs(top - exercise.last_weight_kg) > 0.0005:
                change = weight_text(abs(top - exercise.last_weight_kg), plan.unit)
                view["weight_change"] = ("+" if top > exercise.last_weight_kg else "-") + change
    return in_unit(data, plan.unit)


def user_message(plan: CoachInput | WeeklyInput) -> str:
    language = LANGUAGES[plan.language]
    what = "summary and suggestions" if isinstance(plan, WeeklyInput) else "reasons and summary"
    return (
        f"Write the {what} in {language}. Weights in the input are already in the "
        f"user's unit ({plan.unit}), written as the app shows them: quote them exactly as "
        "given, and never convert, round or recompute a weight."
        "\n\n<input>\n" + json.dumps(model_view(plan), ensure_ascii=False, indent=1) + "\n</input>"
    )


def output_schema(output: type[BaseModel] = CoachOutput) -> dict:
    """The output model as a plain JSON schema that all three providers accept: no
    references or length limits, every property required, no extra properties."""

    def strip(node):
        if isinstance(node, dict):
            node = {k: strip(v) for k, v in node.items() if k not in {"title", "maxLength"}}
            if node.get("type") == "object":
                node["additionalProperties"] = False
                node["required"] = list(node.get("properties", {}))
            return node
        if isinstance(node, list):
            return [strip(item) for item in node]
        return node

    schema = output.model_json_schema()
    defs = schema.pop("$defs", {})

    def inline(node):
        if isinstance(node, dict):
            if "$ref" in node:
                return inline(defs[node["$ref"].split("/")[-1]])
            return {k: inline(v) for k, v in node.items()}
        if isinstance(node, list):
            return [inline(item) for item in node]
        return node

    return strip(inline(schema))
