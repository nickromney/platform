# Sentiment Analysis

This is a deeper DDD pass over `sentiment`.

Compared with `subnetcalc`, the domain is smaller and the request flow is
cleaner.

## Domain Core Versus Supporting Concerns

The domain core is:

- accept comment text
- classify its sentiment
- return label, confidence, and latency
- persist the result
- show recent comment history

Supporting concerns are:

- `oauth2-proxy`
- Keycloak realm and OIDC login
- edge routing between UI and API
- CSV-backed persistence
- SST model loading and warmup

The supporting stack is substantial, but the actual business model is compact.

## Observed User Capabilities

From the API and UI tests, the current capabilities are:

- check health, which also ensures the comment store exists
- submit a comment for analysis
- reject empty comment text
- list recent comments newest first
- display the authenticated user via `oauth2-proxy`
- reuse sample texts to exercise positive, negative, and mixed language paths

The UI is thin. It mainly exposes the current domain result and recent history.

## Candidate Domain Model

Candidate value objects:

- `CommentText`
- `SentimentLabel`
- `ConfidenceScore`
- `AnalysisLatency`
- `CommentRecord`

Candidate domain services:

- `SentimentClassifier`
- `CommentAnalysisPolicy`
- `RecentComments`

Candidate repository boundary:

- `CommentRecordRepository`

Today those concerns are mostly collapsed into one service file, which is fine
for the current size of the app, but the conceptual split is already visible.

## Rules Already Captured In Tests

The current tests describe meaningful domain rules:

- health creates the backing store on first use
- empty text is invalid
- newer comments are returned before older comments
- near-even positive and negative scores collapse to `neutral`
- mixed wording can force `neutral` even when the raw scores are highly polar
- clear positive and negative results stay polar
- the default analyzer is the SST-based path unless explicitly overridden
- warmup happens before the server begins listening

Those rules are visible in
[server.test.js](../../apps/sentiment/api-sentiment/server.test.js) and
[App.test.jsx](../../apps/sentiment/frontend-react-vite/sentiment-auth-ui/src/App.test.jsx).

## The Most Interesting Domain Policy

The most specific business-like rule in `sentiment` today is not the model
choice. It is the neutralization policy:

- detect positive cues
- detect negative cues
- when both coexist, classify as mixed and return `neutral`
- when the positive and negative scores are too close, return `neutral`

That policy is a genuine candidate for an explicit domain service because it is
separate from transport, storage, and identity.

## Identity Is Clearly Outside The Domain Core

The browser always reaches the app through `oauth2-proxy` in the main compose
shape. That is important to the delivered experience, but the core domain does
not need to know OIDC details. The domain only needs a caller identity when the
UI chooses to display it.

That separation is healthy:

- the API classifies comments
- the edge controls access
- the UI renders the user and the result

## What Looks Stable

- comment submission
- sentiment label and confidence
- recent-comment history
- neutralization for mixed or near-even signals

## What Looks Incidental

- CSV as the current persistence mechanism
- the exact model identifier
- the exact OIDC product choice behind the browser gate
- frontend framework details

## Best Next Red Tests In Domain Language

- "Empty comment text is rejected"
- "A mixed-signal comment becomes neutral"
- "Recent comments are shown newest first"
- "Classifier warmup happens before the service is declared ready"
- "Submitting a comment creates a persisted comment record with label,
  confidence, and latency"

## DDD Read

`sentiment` is smaller than `subnetcalc`, but it is actually a very good
teaching context for DDD plus TDD because:

- the request flow is simple
- the core model is easy to isolate
- one explicit policy already stands out from the infrastructure

If the goal is to practice the mechanics of naming and isolating a domain
policy, `sentiment` is the easier starting point. If the goal is to model a
richer domain, `subnetcalc` is the better next step.
