"""The AI coach: adjusts and explains the phone's rule-based next-session plan.

The rules (ios/IronSageKit/Sources/IronSageCore/NextSession.swift) decide the numbers.
The model only picks one of a few allowed adjustments per exercise and writes the
reason; `guardrails.apply` turns that into sets, so a model can never invent a weight.
"""
