"""Runs the coach for one plan, or for one user's week."""

from pydantic import ValidationError

from . import guardrails, prompt
from .providers import CoachModel, RefusedError
from .schemas import CoachInput, CoachOutput, CoachResult, WeeklyInput, WeeklyOutput, WeeklyResult


class CoachError(RuntimeError):
    """No usable advice; the app keeps showing the rule plan without a reason."""


def advise(plan: CoachInput, model: CoachModel, task: str = "next_session") -> CoachResult:
    try:
        completion = model.complete(
            prompt.system_prompt(task), prompt.user_message(plan), prompt.output_schema()
        )
    except RefusedError as error:
        raise CoachError(f"{model.name} declined") from error
    try:
        output = CoachOutput.model_validate_json(completion.text)
        exercises = guardrails.apply(plan, output)
    except (ValidationError, guardrails.InvalidAdvice) as error:
        raise CoachError(f"{model.name}: {error}") from error
    return CoachResult(
        summary=output.summary.strip(),
        exercises=exercises,
        model=model.name,
        input_tokens=completion.input_tokens,
        output_tokens=completion.output_tokens,
    )


def summarize_week(week: WeeklyInput, model: CoachModel) -> WeeklyResult:
    try:
        completion = model.complete(
            prompt.system_prompt("weekly_summary"),
            prompt.user_message(week),
            prompt.output_schema(WeeklyOutput),
        )
    except RefusedError as error:
        raise CoachError(f"{model.name} declined") from error
    try:
        output = guardrails.check_week(week, WeeklyOutput.model_validate_json(completion.text))
    except (ValidationError, guardrails.InvalidAdvice) as error:
        raise CoachError(f"{model.name}: {error}") from error
    return WeeklyResult(
        **output.model_dump(),
        model=model.name,
        input_tokens=completion.input_tokens,
        output_tokens=completion.output_tokens,
    )
