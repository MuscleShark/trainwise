"""Scores a coach model on the eval cases: format, safety, coaching rules, language,
grounded numbers, cost and time. Next-session cases and weekly-summary cases are scored
with their own rules, and the same checks on wording."""

import re
import time
from dataclasses import dataclass, field

from . import guardrails
from .eval_cases import Case, WeeklyCase
from .providers import CoachModel
from .schemas import CoachInput, CoachResult, Readiness, WeeklyInput, WeeklyResult, WeekReadiness
from .service import CoachError, advise, summarize_week

# US dollars per million input and output tokens, checked 2026-10-25 against
# Anthropic's model table. Prices for other providers are passed on the command line.
PRICES = {
    "anthropic:claude-opus-5-5": (4.00, 20.00),
    "anthropic:claude-sonnet-5-5": (2.00, 10.00),
    "anthropic:claude-haiku-5-5": (0.10, 0.50),
}

CJK = re.compile(r"[一-鿿]")
NUMBER = re.compile(r"\d+(?:[.,]\d+)?")


@dataclass
class CaseResult:
    case: str
    failures: list[str] = field(default_factory=list)
    seconds: float = 0.0
    input_tokens: int = 0
    output_tokens: int = 0
    result: CoachResult | WeeklyResult | None = None

    @property
    def passed(self) -> bool:
        return not self.failures


# Plate steps a reason may name ("the 2.5 kg increase"), in kilograms and pounds.
PLATE_STEPS = {1.25, 2.5, 5.0, 10.0}


def minutes_as_text(minutes: float) -> set[float]:
    """The numbers a duration can be written with: 135 minutes is 135, 2, 15, 2.3 or 2.5."""
    hours = minutes / 60
    return {
        round(minutes),
        int(hours),
        round(hours),
        round(hours, 1),
        round(minutes % 60),
        round(hours * 2) / 2,
    }


def allowed_numbers(plan: CoachInput) -> set[float]:
    """Numbers a reason may mention: everything in the input, weights also in pounds,
    plate steps and the change between last time and the plan, sleep as hours and
    minutes, the difference between each readiness value and its usual (also as a
    percentage), and small counts such as "one more rep"."""
    numbers: set[float] = set(range(0, 11)) | PLATE_STEPS
    for text in NUMBER.findall(plan.model_dump_json()):
        numbers.add(float(text.replace(",", ".")))
    weights = [
        s.weight_kg
        for e in plan.exercises
        for s in [*e.planned_sets, *(d for session in e.recent_sessions for d in session.sets)]
        if s.weight_kg
    ]
    for kg in weights:
        lb = kg / 0.45359237
        numbers.update({round(lb), round(lb * 2) / 2, round(lb, 1), round(lb / 2.5) * 2.5})
    for exercise in plan.exercises:
        top = max((s.weight_kg or 0 for s in exercise.planned_sets), default=0)
        if exercise.last_weight_kg and top:
            change = abs(top - exercise.last_weight_kg)
            numbers.update(
                {change, round(change / 0.45359237), round(change / 0.45359237 / 2.5) * 2.5}
            )
    return numbers | readiness_numbers(plan.readiness)


def readiness_numbers(readiness: Readiness | WeekReadiness) -> set[float]:
    """Sleep as hours and minutes, and the difference between each readiness value and
    its usual, also as a percentage."""
    numbers: set[float] = set()
    if readiness.sleep_minutes:
        sleep = readiness.sleep_minutes
        for minutes in (sleep.value, sleep.usual):
            if minutes is not None:
                numbers.update(minutes_as_text(minutes))
        if sleep.usual is not None:
            numbers.update(minutes_as_text(abs(sleep.usual - sleep.value)))
    for metric in (readiness.hrv_ms, readiness.resting_hr_bpm, readiness.sleep_minutes):
        if metric and metric.usual:
            difference = abs(metric.usual - metric.value)
            numbers.update({round(difference), round(difference / metric.usual * 100)})
    return numbers


def check(case: Case, result: CoachResult) -> list[str]:
    failures = []
    plan_by_id = {e.exercise_id: e for e in case.plan.exercises}
    texts = [result.summary, *(e.reason for e in result.exercises)]

    for final in result.exercises:
        planned = plan_by_id[final.exercise_id]
        if final.action not in case.allowed[final.exercise_id]:
            failures.append(f"{final.exercise_id}: {final.action.value} not allowed here")
        top_planned = max((s.weight_kg or 0 for s in planned.planned_sets), default=0)
        if any((s.weight_kg or 0) > top_planned + 0.0005 for s in final.sets):
            failures.append(f"{final.exercise_id}: weight above the rule plan")
        if not final.reason:
            failures.append(f"{final.exercise_id}: no reason")

    return failures + text_failures(
        texts, case.plan.language, allowed_numbers(case.plan), case.forbidden
    )


def text_failures(
    texts: list[str], language: str, allowed: set[float], forbidden: list[str]
) -> list[str]:
    """The checks every task's wording gets: language, numbers and forbidden phrases."""
    failures = []
    joined = " ".join(texts)
    if language == "zh" and not CJK.search(joined):
        failures.append("not in Chinese")
    if language == "en" and CJK.search(joined):
        failures.append("Chinese in an English answer")

    for text in texts:
        for number in NUMBER.findall(text):
            value = float(number.replace(",", "."))
            if not any(abs(value - a) < 0.051 for a in allowed):
                failures.append(f"number not in the input: {number} in “{text}”")

    for phrase in forbidden:
        if phrase in joined:
            failures.append(f"repeated {phrase!r}")
    return failures


DELOAD_WORDS = guardrails.DELOAD_WORDS
# A sentence ends with one of these, followed by a space or the end of the text.
SENTENCE_END = re.compile(r"[.!?](?=\s|$)|[。！？]")


def allowed_week_numbers(week: WeeklyInput) -> set[float]:
    """Numbers a weekly summary may mention: everything in the input, record weights
    also in pounds, sleep as hours and minutes, differences from usual, and small
    counts such as "two or three more sets"."""
    numbers: set[float] = set(range(0, 11)) | PLATE_STEPS
    for text in NUMBER.findall(week.model_dump_json()):
        numbers.add(float(text.replace(",", ".")))
    for record in week.records:
        lb = record.weight_kg / 0.45359237
        numbers.update({round(lb), round(lb * 2) / 2, round(lb, 1), round(lb / 2.5) * 2.5})
    return numbers | readiness_numbers(week.readiness)


def check_week(case: WeeklyCase, result: WeeklyResult) -> list[str]:
    failures = []
    sentences = len(SENTENCE_END.findall(result.summary.strip()))
    if not 3 <= sentences <= 5:
        failures.append(f"summary has {sentences} sentences, not 3 to 5")
    if result.deload != case.week.deload_suggested:
        failures.append(
            "no lighter week although the rules suggest one"
            if case.week.deload_suggested
            else "a lighter week the rules didn't suggest"
        )
    texts = [result.summary, *result.suggestions]
    lowered = " ".join(texts).lower()
    if not case.week.deload_suggested and any(word in lowered for word in DELOAD_WORDS):
        failures.append("mentions a lighter week the rules didn't suggest")
    return failures + text_failures(
        texts, case.week.language, allowed_week_numbers(case.week), case.forbidden
    )


def run_case(case: Case | WeeklyCase, model: CoachModel) -> CaseResult:
    started = time.perf_counter()
    outcome = CaseResult(case.name)
    try:
        if isinstance(case, WeeklyCase):
            result = summarize_week(case.week, model)
        else:
            result = advise(case.plan, model)
    except CoachError as error:
        outcome.failures.append(f"no usable answer: {error}")
    else:
        outcome.result = result
        outcome.input_tokens = result.input_tokens
        outcome.output_tokens = result.output_tokens
        outcome.failures = (
            check_week(case, result) if isinstance(case, WeeklyCase) else check(case, result)
        )
    outcome.seconds = time.perf_counter() - started
    return outcome


@dataclass
class Report:
    model: str
    results: list[CaseResult]
    price: tuple[float, float] | None = None

    @property
    def pass_rate(self) -> float:
        return sum(r.passed for r in self.results) / len(self.results) if self.results else 0.0

    @property
    def cost_per_case(self) -> float | None:
        if self.price is None or not self.results:
            return None
        tokens_in = sum(r.input_tokens for r in self.results)
        tokens_out = sum(r.output_tokens for r in self.results)
        total = tokens_in / 1e6 * self.price[0] + tokens_out / 1e6 * self.price[1]
        return total / len(self.results)

    @property
    def median_seconds(self) -> float:
        times = sorted(r.seconds for r in self.results)
        return times[len(times) // 2] if times else 0.0


def evaluate(
    model: CoachModel,
    cases: list[Case] | list[WeeklyCase],
    price: tuple[float, float] | None = None,
) -> Report:
    return Report(
        model.name, [run_case(case, model) for case in cases], price or PRICES.get(model.name)
    )


def answers(reports: list[Report]) -> str:
    """Every summary and reason, by case, so people can judge the wording."""
    lines = []
    for report in reports:
        lines += [f"## {report.model}", ""]
        for outcome in report.results:
            mark = "✓" if outcome.passed else "✗"
            lines.append(f"### {mark} {outcome.case}")
            if outcome.result is None:
                lines += ["", f"No answer: {'; '.join(outcome.failures)}", ""]
                continue
            lines += ["", f"> {outcome.result.summary}", ""]
            if isinstance(outcome.result, WeeklyResult):
                if outcome.result.deload:
                    lines.append("Lighter week suggested.")
                lines += [f"- {text}" for text in outcome.result.suggestions]
            else:
                for item in outcome.result.exercises:
                    lines.append(f"- **{item.exercise_id}** ({item.action.value}): {item.reason}")
            lines.append("")
    return "\n".join(lines)


def markdown(reports: list[Report], what: str = "suggestion") -> str:
    lines = [
        f"| Model | Passed | Cost per {what} | Median time |",
        "|---|---|---|---|",
    ]
    for report in reports:
        cost = (
            f"${report.cost_per_case:.4f}" if report.cost_per_case is not None else "price not set"
        )
        passed = sum(r.passed for r in report.results)
        lines.append(
            f"| {report.model} | {passed}/{len(report.results)} ({report.pass_rate:.0%}) "
            f"| {cost} | {report.median_seconds:.1f} s |"
        )
    for report in reports:
        failed = [r for r in report.results if not r.passed]
        if failed:
            lines += ["", f"### Failures: {report.model}", ""]
            lines += [f"- {r.case}: {'; '.join(r.failures)}" for r in failed]
    return "\n".join(lines) + "\n"
