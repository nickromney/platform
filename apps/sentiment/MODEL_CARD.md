# Sentiment Demo Model Card

## Purpose

The sentiment app is a local IDP workload used to exercise deployment,
observability, policy, and identity paths. Its model output is demonstration
data, not a production decision system.

## Evaluation Fixture

The lightweight evaluation fixture is `evaluation.jsonl`. It covers one
positive, one negative, and one neutral platform-operations sentence so the
app has a concrete regression surface.

## Operational Boundaries

- Do not use the demo output for user-impacting decisions.
- Keep model downloads out of the request path.
- Treat evaluation data as source-controlled test input.
- Use app/environment RBAC groups for access to the running service.
