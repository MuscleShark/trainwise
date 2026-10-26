"""Runs the coach eval against real models and prints a Markdown report.

Needs the provider SDKs (pip install -r requirements-coach.txt) and the API keys in
the environment: ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY. Every run costs
money; the 24 next-session cases or the 18 weekly-summary cases are a few cents per
model.

    python scripts/coach_eval.py anthropic:claude-opus-5-5 openai:gpt-6-astra \\
        google:gemini-3.8-flash --price openai:gpt-6-astra=IN,OUT --out eval.md
    python scripts/coach_eval.py anthropic:claude-sonnet-5-5 --task weekly_summary
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from coach import evaluation, providers  # noqa: E402
from coach.eval_cases import cases, weekly_cases  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("models", nargs="+", help="provider:model")
    parser.add_argument(
        "--price",
        action="append",
        default=[],
        help="provider:model=input,output in USD per million tokens",
    )
    parser.add_argument(
        "--task",
        choices=["next_session", "weekly_summary"],
        default="next_session",
        help="which coach task to evaluate",
    )
    parser.add_argument("--only", help="run only cases whose name contains this")
    parser.add_argument("--out", type=Path, help="also write the report to this file")
    parser.add_argument(
        "--answers", type=Path, help="write every summary and reason to this file, to read"
    )
    args = parser.parse_args()

    prices = {}
    for entry in args.price:
        spec, _, numbers = entry.partition("=")
        price_in, price_out = (float(n) for n in numbers.split(","))
        prices[spec] = (price_in, price_out)

    every = weekly_cases() if args.task == "weekly_summary" else cases()
    selected = [c for c in every if not args.only or args.only in c.name]
    reports = []
    for spec in args.models:
        print(f"Running {len(selected)} cases on {spec}…", file=sys.stderr)
        reports.append(evaluation.evaluate(providers.model(spec), selected, prices.get(spec)))
    report = evaluation.markdown(
        reports, "summary" if args.task == "weekly_summary" else "suggestion"
    )
    print(report)
    if args.out:
        args.out.write_text(report, encoding="utf-8")
    if args.answers:
        args.answers.write_text(evaluation.answers(reports), encoding="utf-8")


if __name__ == "__main__":
    main()
