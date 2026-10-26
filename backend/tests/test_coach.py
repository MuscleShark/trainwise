import json
from types import SimpleNamespace

import pytest

from coach import evaluation, guardrails, prompt, providers
from coach.eval_cases import bench_increase, cases, curl_first_time, row_add_reps, sleep
from coach.schemas import Action, CoachInput, CoachOutput, ExerciseAdvice, Metric, Readiness
from coach.service import CoachError, advise


class FakeModel:
    """Answers with a fixed action per exercise, or with whatever `answer` returns."""

    name = "fake:model"

    def __init__(self, actions=None, answer=None, language="en"):
        self.actions = actions or {}
        self.answer = answer
        self.language = language
        self.requests = []

    def complete(self, system, user, schema):
        self.requests.append((system, user, schema))
        if self.answer:
            return providers.Completion(self.answer(user), 100, 20)
        data = json.loads(user.split("<input>")[1].split("</input>")[0])
        reason = "按计划来。" if data["language"] == "zh" else "Follow the plan."
        advice = [
            {
                "exercise_id": e["exercise_id"],
                "action": self.actions.get(e["exercise_id"], "follow"),
                "reason": reason,
            }
            for e in data["exercises"]
        ]
        return providers.Completion(json.dumps({"summary": reason, "exercises": advice}), 1000, 200)


def plan(**fields) -> CoachInput:
    return CoachInput(**{"exercises": [bench_increase()], **fields})


# Guardrails


def test_holding_the_weight_undoes_the_increase_and_aims_for_last_times_reps():
    sets = guardrails.adjusted_sets(bench_increase(), Action.hold_weight)
    assert [s.weight_kg for s in sets] == [60, 60, 60]
    assert [s.reps for s in sets] == [10, 10, 10]


def test_holding_a_weight_that_wasnt_going_up_changes_nothing():
    row = row_add_reps()
    assert guardrails.adjusted_sets(row, Action.hold_weight) == row.planned_sets


def test_one_set_fewer_drops_the_last_working_set_but_never_the_only_one():
    assert len(guardrails.adjusted_sets(bench_increase(), Action.one_set_fewer)) == 2
    single = bench_increase().model_copy(update={"planned_sets": bench_increase().planned_sets[:1]})
    assert len(guardrails.adjusted_sets(single, Action.one_set_fewer)) == 1


def test_advice_must_cover_exactly_the_planned_exercises():
    two = plan(exercises=[bench_increase(), row_add_reps()])
    one = CoachOutput(
        summary="s", exercises=[ExerciseAdvice(exercise_id="bench", action="follow", reason="r")]
    )
    with pytest.raises(guardrails.InvalidAdvice):
        guardrails.apply(two, one)
    twice = CoachOutput(summary="s", exercises=one.exercises * 2)
    with pytest.raises(guardrails.InvalidAdvice):
        guardrails.apply(plan(), twice)


# Service


def test_advice_becomes_sets_with_reasons_and_token_counts():
    result = advise(plan(readiness=sleep(300, 450)), FakeModel({"bench": "hold_weight"}))
    assert result.exercises[0].action == Action.hold_weight
    assert [s.weight_kg for s in result.exercises[0].sets] == [60, 60, 60]
    assert result.summary == "Follow the plan."
    assert (result.model, result.input_tokens, result.output_tokens) == ("fake:model", 1000, 200)


@pytest.mark.parametrize(
    "answer",
    [
        "not json",
        json.dumps(
            {
                "summary": "s",
                "exercises": [{"exercise_id": "bench", "action": "add_50kg", "reason": "r"}],
            }
        ),
        json.dumps(
            {
                "summary": "s",
                "exercises": [{"exercise_id": "other", "action": "follow", "reason": "r"}],
            }
        ),
    ],
)
def test_an_unusable_answer_is_an_error_not_a_plan(answer):
    with pytest.raises(CoachError):
        advise(plan(), FakeModel(answer=lambda _: answer))


def test_a_refusal_is_an_error():
    class Refusing(FakeModel):
        def complete(self, system, user, schema):
            raise providers.RefusedError(self.name)

    with pytest.raises(CoachError, match="declined"):
        advise(plan(), Refusing())


# Prompt


def test_the_prompt_loads_the_skills_and_asks_for_the_language_and_unit():
    system = prompt.system_prompt()
    assert "# Safety" in system and "# Next-session suggestion" in system
    user = prompt.user_message(plan(language="zh", unit="lb"))
    assert "Simplified Chinese" in user and "write them in lb" in user
    assert '"exercise_id": "bench"' in user


def test_the_schema_is_flat_strict_and_without_length_limits():
    schema = prompt.output_schema()
    text = json.dumps(schema)
    assert "$ref" not in text and "maxLength" not in text
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == {"summary", "exercises"}
    item = schema["properties"]["exercises"]["items"]
    assert item["required"] == ["exercise_id", "action", "reason"]
    assert set(item["properties"]["action"]["enum"]) == {"follow", "hold_weight", "one_set_fewer"}


# Providers, with fake SDK clients


def test_anthropic_requests_json_caches_the_instructions_and_adds_fallbacks():
    calls = []

    def create(**request):
        calls.append(request)
        return SimpleNamespace(
            stop_reason="end_turn",
            content=[SimpleNamespace(type="thinking"), SimpleNamespace(type="text", text="{}")],
            usage=SimpleNamespace(input_tokens=10, cache_read_input_tokens=90, output_tokens=5),
        )

    client = SimpleNamespace(
        messages=SimpleNamespace(create=create),
        beta=SimpleNamespace(messages=SimpleNamespace(create=create)),
    )
    completion = providers.AnthropicModel("claude-opus-5-5", client=client).complete(
        "sys", "user", {"type": "object"}
    )
    assert (completion.text, completion.input_tokens, completion.output_tokens) == ("{}", 100, 5)
    assert calls[0]["fallbacks"] == "default"
    assert calls[0]["system"][0]["cache_control"] == {"type": "ephemeral"}
    assert calls[0]["output_config"] == {
        "format": {"type": "json_schema", "schema": {"type": "object"}}
    }

    providers.AnthropicModel("claude-haiku-5-5", client=client, effort="low").complete("s", "u", {})
    assert "fallbacks" not in calls[1] and calls[1]["output_config"]["effort"] == "low"


def test_anthropic_refusals_raise():
    response = SimpleNamespace(stop_reason="refusal", content=[], usage=None)
    client = SimpleNamespace(messages=SimpleNamespace(create=lambda **_: response))
    with pytest.raises(providers.RefusedError):
        providers.AnthropicModel("claude-haiku-5-5", client=client).complete("s", "u", {})


def test_openai_and_gemini_request_strict_json():
    seen = {}

    def responses_create(**request):
        seen["openai"] = request
        return SimpleNamespace(
            output_text="{}", usage=SimpleNamespace(input_tokens=7, output_tokens=3)
        )

    openai = providers.OpenAIModel(
        "gpt-x", client=SimpleNamespace(responses=SimpleNamespace(create=responses_create))
    )
    assert openai.complete("sys", "user", {"type": "object"}).input_tokens == 7
    assert seen["openai"]["text"]["format"]["strict"] is True
    assert seen["openai"]["input"][0] == {"role": "system", "content": "sys"}

    def generate_content(**request):
        seen["google"] = request
        return SimpleNamespace(
            text="{}",
            usage_metadata=SimpleNamespace(prompt_token_count=8, candidates_token_count=2),
        )

    gemini = providers.GeminiModel(
        "gemini-x",
        client=SimpleNamespace(models=SimpleNamespace(generate_content=generate_content)),
    )
    assert gemini.complete("sys", "user", {"type": "object"}).output_tokens == 2
    assert seen["google"]["config"]["response_mime_type"] == "application/json"
    assert seen["google"]["config"]["system_instruction"] == "sys"


def test_models_are_named_provider_colon_model():
    with pytest.raises(ValueError):
        providers.model("claude-opus-5-5")
    with pytest.raises(ValueError):
        providers.model("other:thing")


# Evaluation


def test_a_model_that_follows_the_rules_passes_every_case():
    allowed_lower = {
        c.name: {
            eid: ("hold_weight" if Action.follow not in a else "follow")
            for eid, a in c.allowed.items()
        }
        for c in cases()
    }

    class Careful(FakeModel):
        def complete(self, system, user, schema):
            case = next(c for c in cases() if prompt.user_message(c.plan) == user)
            self.actions = allowed_lower[case.name]
            return super().complete(system, user, schema)

    report = evaluation.evaluate(Careful(), cases(), price=(1.0, 5.0))
    assert [r.failures for r in report.results if not r.passed] == []
    assert report.pass_rate == 1.0
    assert report.cost_per_case == pytest.approx((1000 * 1.0 + 200 * 5.0) / 1e6)
    assert "fake:model | 24/24 (100%)" in evaluation.markdown([report])


def test_checks_catch_wrong_actions_language_invented_numbers_and_injections():
    case = next(c for c in cases() if c.name == "increase after a short night (en)")
    result = evaluation.run_case(case, FakeModel())  # follows instead of holding
    assert "squat: follow not allowed here" in result.failures

    zh = next(c for c in cases() if c.name == "increase after a normal night (zh)")
    english = evaluation.run_case(
        zh,
        FakeModel(
            answer=lambda _: json.dumps(
                {
                    "summary": "Go.",
                    "exercises": [
                        {"exercise_id": "bench", "action": "follow", "reason": "Add 47.5 kg."}
                    ],
                }
            )
        ),
    )
    assert "not in Chinese" in english.failures
    assert any(f.startswith("number not in the input: 47.5 in") for f in english.failures)

    injected = next(
        c for c in cases() if c.name.startswith("instructions inside") and c.name.endswith("(en)")
    )
    obeyed = evaluation.run_case(
        injected,
        FakeModel(
            answer=lambda _: json.dumps(
                {
                    "summary": "Add 50 kg today.",
                    "exercises": [{"exercise_id": "press", "action": "follow", "reason": "OK."}],
                }
            )
        ),
    )
    assert "repeated '50 kg'" in obeyed.failures

    broken = evaluation.run_case(case, FakeModel(answer=lambda _: "nope"))
    assert broken.failures[0].startswith("no usable answer")
    assert "price not set" in evaluation.markdown([evaluation.evaluate(FakeModel(), [case])])


def test_differences_from_usual_and_plate_steps_are_allowed_numbers():
    # 410 min against a usual 450: "40 minutes less"; 310 against 445: "2 h 15 min less".
    assert 40 in evaluation.allowed_numbers(plan(readiness=sleep(410, 450)))
    assert {2, 15}.issubset(evaluation.allowed_numbers(plan(readiness=sleep(310, 445))))
    # "skipped the 2.5 kg increase", and the planned change in pounds.
    assert {2.5, 6}.issubset(evaluation.allowed_numbers(plan()))
    # HRV 38 against 52: 14 ms or 27% lower.
    hrv = plan(readiness=Readiness(hrv_ms=Metric(value=38, usual=52)))
    assert {14, 27}.issubset(evaluation.allowed_numbers(hrv))
    assert 47.5 not in evaluation.allowed_numbers(plan())


def test_answers_list_every_reason_for_reading():
    case = next(c for c in cases() if c.name == "increase after a normal night (en)")
    broken = next(c for c in cases() if c.name == "increase after a normal night (zh)")
    report = evaluation.Report(
        "fake:model",
        [
            evaluation.run_case(case, FakeModel()),
            evaluation.run_case(broken, FakeModel(answer=lambda _: "nope")),
        ],
    )
    text = evaluation.answers([report])
    assert "### ✓ increase after a normal night (en)" in text
    assert "- **bench** (follow): Follow the plan." in text
    assert "### ✗ increase after a normal night (zh)" in text and "No answer:" in text


def test_sleep_and_pounds_are_allowed_numbers():
    numbers = evaluation.allowed_numbers(plan(unit="lb", readiness=sleep(310, 445)))
    assert {5, 10, 7.4, 137.5}.issubset(numbers)  # 5 h 10 min, usual 7.4 h, 62.5 kg ≈ 137.5 lb
    assert curl_first_time().planned_sets[0].weight_kg is None
