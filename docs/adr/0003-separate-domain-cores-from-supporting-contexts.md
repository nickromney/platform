# ADR 0003: Separate app domain cores from delivery, identity, and mediation

- Status: Accepted (retrospective)
- Recorded: 2026-04-21

## Context

The repo contains application domains with real rules, but those domains are
surrounded by delivery and platform concerns:

- `subnetcalc` has multiple frontends, multiple backend delivery shapes,
  multiple auth methods, and an APIM-mediated path
- `sentiment` has a thinner core model, but still arrives through
  `oauth2-proxy`, OIDC, edge routing, and compose/Kubernetes runtime choices
- `apim-simulator` brings its own contracts and policy language

The DDD analysis already shows that the domain cores are narrower than the
hosting matrix around them.

## Decision

Model application meaning separately from the supporting contexts that deliver
it.

In practice:

- `subnetcalc` owns network-analysis language and rules
- `sentiment` owns comment-classification language and rules
- identity, frontend routing, APIM mediation, and stack provisioning remain
  supporting contexts at the boundary
- frontend orchestration terms such as `lookup` stay out of the backend domain
  core unless they become explicit domain concepts later

## Consequences

- Transport and auth changes do not automatically force domain-language changes.
- Domain tests can stay focused on business rules instead of stack topology.
- Supporting contexts can be swapped or refactored without collapsing the app
  ubiquitous language into infrastructure jargon.
- APIM remains a separate language at the boundary instead of becoming a hidden
  part of `subnetcalc`.

## Evidence

- [docs/ddd/context-map.md](../ddd/context-map.md)
- [docs/ddd/subnetcalc-analysis.md](../ddd/subnetcalc-analysis.md)
- [docs/ddd/sentiment-analysis.md](../ddd/sentiment-analysis.md)
- [apps/subnetcalc/README.md](../../apps/subnetcalc/README.md)
- [apps/sentiment/README.md](../../apps/sentiment/README.md)
