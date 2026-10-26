"""One small adapter per AI provider, so the provider is a setting.

Each adapter sends the system prompt and the user message, asks for JSON that follows
the output schema, and returns the text and token counts. The SDKs are imported only
when an adapter is created, so the API doesn't need them installed. Tests pass a fake
client instead.
"""

from dataclasses import dataclass
from typing import Protocol


@dataclass
class Completion:
    text: str
    input_tokens: int = 0
    output_tokens: int = 0


class CoachModel(Protocol):
    name: str

    def complete(self, system: str, user: str, schema: dict) -> Completion: ...


class RefusedError(RuntimeError):
    """The provider declined to answer."""


class AnthropicModel:
    # Models that accept server-side refusal fallbacks: a declined request is re-run
    # on another model inside the same call instead of failing.
    FALLBACK_MODELS = {"claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"}

    def __init__(self, model: str, client=None, effort: str | None = None):
        if client is None:
            import anthropic

            client = anthropic.Anthropic()
        self.client = client
        self.model = model
        self.effort = effort
        self.name = f"anthropic:{model}"

    def complete(self, system: str, user: str, schema: dict) -> Completion:
        output_config: dict = {"format": {"type": "json_schema", "schema": schema}}
        if self.effort:
            output_config["effort"] = self.effort
        request = dict(
            model=self.model,
            max_tokens=4000,
            # The system prompt is the same for every request: cache it.
            system=[{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
            messages=[{"role": "user", "content": user}],
            output_config=output_config,
        )
        if self.model in self.FALLBACK_MODELS:
            response = self.client.beta.messages.create(
                **request, betas=["server-side-fallback-2026-07-01"], fallbacks="default"
            )
        else:
            response = self.client.messages.create(**request)
        if response.stop_reason == "refusal":
            raise RefusedError(self.name)
        text = next(block.text for block in response.content if block.type == "text")
        usage = response.usage
        input_tokens = (
            usage.input_tokens
            + (getattr(usage, "cache_read_input_tokens", 0) or 0)
            + (getattr(usage, "cache_creation_input_tokens", 0) or 0)
        )
        return Completion(text, input_tokens, usage.output_tokens)


class OpenAIModel:
    def __init__(self, model: str, client=None):
        if client is None:
            import openai

            client = openai.OpenAI()
        self.client = client
        self.model = model
        self.name = f"openai:{model}"

    def complete(self, system: str, user: str, schema: dict) -> Completion:
        response = self.client.responses.create(
            model=self.model,
            input=[{"role": "system", "content": system}, {"role": "user", "content": user}],
            text={
                "format": {
                    "type": "json_schema",
                    "name": "coach_advice",
                    "schema": schema,
                    "strict": True,
                }
            },
        )
        usage = getattr(response, "usage", None)
        return Completion(
            response.output_text,
            getattr(usage, "input_tokens", 0) or 0,
            getattr(usage, "output_tokens", 0) or 0,
        )


class GeminiModel:
    def __init__(self, model: str, client=None):
        if client is None:
            from google import genai

            client = genai.Client()
        self.client = client
        self.model = model
        self.name = f"google:{model}"

    def complete(self, system: str, user: str, schema: dict) -> Completion:
        response = self.client.models.generate_content(
            model=self.model,
            contents=user,
            config={
                "system_instruction": system,
                "response_mime_type": "application/json",
                "response_json_schema": schema,
            },
        )
        usage = getattr(response, "usage_metadata", None)
        return Completion(
            response.text,
            getattr(usage, "prompt_token_count", 0) or 0,
            getattr(usage, "candidates_token_count", 0) or 0,
        )


PROVIDERS = {"anthropic": AnthropicModel, "openai": OpenAIModel, "google": GeminiModel}

# The model used in production, chosen with the eval (docs/architecture.md, M3 decisions).
DEFAULT_MODEL = "anthropic:claude-sonnet-5-5"


def model(spec: str) -> CoachModel:
    """ "anthropic:claude-opus-5-5", "openai:gpt-6-astra", "google:gemini-3.8-flash"."""
    provider, _, name = spec.partition(":")
    if provider not in PROVIDERS or not name:
        raise ValueError(f"unknown model {spec!r}; use provider:model with {sorted(PROVIDERS)}")
    return PROVIDERS[provider](name)
