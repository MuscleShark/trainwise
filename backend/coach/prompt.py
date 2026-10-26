"""The instructions and input sent to the model.

Instructions live in Markdown "skills" under coach/skills/, loaded by the task they
belong to. They are plain text, so they work the same with every provider.
"""

import json
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


def user_message(plan: CoachInput | WeeklyInput) -> str:
    language = LANGUAGES[plan.language]
    what = "summary and suggestions" if isinstance(plan, WeeklyInput) else "reasons and summary"
    data = plan.model_dump(mode="json", exclude_none=True)
    return (
        f"Write the {what} in {language}. Weights in the input are in "
        f"kilograms; write them in {plan.unit} (1 kg = 2.2046 lb), rounded as on the "
        "plate.\n\n<input>\n" + json.dumps(data, ensure_ascii=False, indent=1) + "\n</input>"
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
