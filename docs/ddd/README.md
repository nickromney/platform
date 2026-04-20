# DDD Starter Notes

This directory is a lightweight starting point for applying Domain-Driven
Design to the current solution.

The main distinction in these notes is between:

- the current implementation and test dialect
- the current operator and platform-stack dialect
- the candidate domain language that should be owned by the domain expert

The repo already contains precise operational language in Makefiles, status
helpers, stack checks, and BATS tests. That language is useful evidence, but
it is not automatically the same thing as the ubiquitous language.

These notes therefore treat the current repo as a source of signals to refine,
not as a source of final truth.

## Artifacts

- [Ubiquitous Language](./ubiquitous-language.md)
- [Context Map](./context-map.md)
- [Solution Variant Comparison](./solution-variant-comparison.md)
- [Subnetcalc Analysis](./subnetcalc-analysis.md)
- [Sentiment Analysis](./sentiment-analysis.md)

## Current Read Of The Solution

- The repo's primary current concern is local stack operation: bringing up and
  managing a useful solution variant on one machine.
- The clearest problem-domain model inside the repo today is
  `subnetcalc`.
- `apps/sentiment` is a smaller domain with a simpler model and cleaner
  request flow.
- Identity, routing, and API mediation appear as important supporting
  contexts between the user and the app domains.
- The current BATS coverage mostly specifies execution contracts, helper
  delegation, machine ownership, and variant readiness. That is valuable, but
  it should not be mistaken for the final domain language.

`platform` still works in these notes as the repo/theme word. The sharper path
taxonomy is `solution` first, then `variant`.

## What These Notes Are For

- Make the current language visible.
- Expose vocabulary collisions early.
- Separate business meaning from hosting and topology details.
- Give TDD a better target by naming scenarios in domain language first.

## Likely Next Passes

- Ratify canonical terms with the domain expert.
- Replace overloaded implementation terms where possible.
- Write example scenarios in domain language before changing structure.
- Use those scenarios as the red tests for subsequent refactors.
