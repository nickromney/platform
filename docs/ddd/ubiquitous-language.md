# Ubiquitous Language

This is the canonical vocabulary for the repo.

It is split into two layers:

- the implementation and test language that exists today
- the domain language that the code should converge on

The goal is to **make the code and the glossary consistent**. Where they still
diverge, the gap is tracked in
[consistency-plan.md](./consistency-plan.md) with an explicit direction of
travel (update the code, update the glossary, or leave both and accept the
overload).

Wire-visible contracts stay frozen until a planned version bump — see
[contracts.md](./contracts.md) for the breaking-change surfaces.

## Translation From Current Test And Operator Dialect

| Current term | Candidate meaning | Notes |
| --- | --- | --- |
| active variant surface | the active variant currently owning the local stack | In repo terms today this usually means a path such as `kubernetes/kind` or `kubernetes/lima`. |
| active variant path | the active solution/variant path | Seen in machine-ownership checks such as `kubernetes/kind` or `kubernetes/lima`. |
| claimed by | currently owns the shared local ingress surface | Expresses machine ownership more than business value. |
| shared host ports | the scarce local edge resource that only one variant should own at a time | Useful operational concept; poor business term. |
| blocked | a safety precondition failed and operation should not continue | Good concept, but implementation-heavy in current tests. |
| prereqs | operator readiness check | Better thought of as "am I ready to operate the platform?" |
| check-health | variant readiness check | Better thought of as "is the current variant ready?" |
| stage | the cumulative build ladder | `100` through `900` are the canonical stage values. |
| stack | currently overloaded between compose slices, full platform shape, and app demos | The domain language should narrow this to the whole collection of apps realized for a solution variant. |
| status | variant ownership and readiness snapshot | Current tests use this in a machine-oriented sense. |

## Ratified Terms

| Proposed term | Current meaning in the solution | Aliases or ambiguity |
| --- | --- | --- |
| platform | the repo/theme word for patterns that platform engineers may reuse | Useful broad label, but not the sharp path taxonomy term inside this repo. |
| solution | the first-level grouping such as `kubernetes` or `sd-wan` | The repo is grouped by what you want to run. |
| variant | the concrete operable path beneath a solution | Examples: `kubernetes/kind`, `kubernetes/lima`, `kubernetes/slicer`. |
| target | a Makefile and workflow noun | Keep this implementation-facing term, but do not use it as the main DDD taxonomy label. |
| stack | the whole collection of apps realized for a solution variant | Closest analogy is a full Compose deployment shape. |
| stage | the cumulative build ladder on a solution variant | Examples: `100` through `900`. |
| provider | reserved for Terraform provider discussions | Should not be used for `kind`, `lima`, or `slicer`. |
| environment | the app exposure or testing band | Examples: `dev`, `sit`, `uat`, `admin`. |
| workload | a deployed app unit or image | Mostly platform-facing language. |
| readiness | whether a variant can be safely operated or verified now | Spread across `prereqs`, `status`, and `check-*` commands. |
| blocker | a concrete reason an operation should stop | Strong and useful term. |
| ownership | which variant currently owns shared local ingress | Currently expressed indirectly through status output. |

## Ratified Stage Labels

| Stage | Preferred label | Notes |
| --- | --- | --- |
| `100` | cluster available | Outcome-first language fits infrastructure-as-code better than `bootstrap`. |
| `200` | Cilium | Keep the product name. |
| `300` | Hubble | Keep the product name. |
| `400` | Argo CD | Keep the product name. |
| `500` | Gitea | Keep the product name. |
| `600` | policies | Still the clearest short label. |
| `700` | app repos | Better than `supply chain`; this is where GitOps gets real app sources. |
| `800` | observability | This stage currently also turns on gateway TLS and Headlamp. |
| `900` | SSO | This stage also wires the access path used by Headlamp-ready API trust. |

## Identity And Access Language

| Proposed term | Current meaning in the solution | Aliases or ambiguity |
| --- | --- | --- |
| identity service | the system that authenticates the user | Implemented by Dex in-cluster and Keycloak in compose. |
| `oauth2-proxy` | the browser-facing auth front door | Keep the product name in the ubiquitous language for this repo. |
| SSO | authenticated entry through OIDC plus session cookies | Used consistently, but mixes business and product names. |
| realm | identity namespace | `sentiment` should use a `sentiment` realm. |
| auth method | the backend auth strategy | `none`, `api_key`, `jwt`, `azure_swa`, `apim`, `azure_ad`. |
| session | authenticated browser state | Usually represented by cookies. |
| user info | authenticated user payload passed downstream | Appears as `/oauth2/userinfo` or forwarded headers. |
| login | begin an authenticated session | Can be app-managed, platform-managed, or proxy-managed depending on stack. |
| logout | end the current session | Currently expressed through proxy or platform endpoints. |
| Easy Auth | platform-managed auth flow | Azure-specific term that should stay inside this context. |

## Subnet Analysis Language

| Proposed term | Current meaning in the solution | Aliases or ambiguity |
| --- | --- | --- |
| subnetcalc | the canonical network-analysis application name | The current repo path is still `apps/subnetcalc`, but the agreed product term is `subnetcalc`. |
| address | a single IPv4 or IPv6 address | Clear in the code and API. |
| network | a CIDR block under analysis | Sometimes end users may call this a subnet. |
| CIDR | network notation such as `192.168.1.0/24` | Stable domain term. |
| validation | checking that an address or network is well formed | Currently a distinct endpoint. |
| private range | RFC1918 address space | IPv4-focused in the current model. |
| shared address space | RFC6598 range | Useful distinction already present in code. |
| Cloudflare range check | whether an address falls within Cloudflare ranges | Currently modeled as a separate check. |
| cloud mode | reservation rules for a target cloud | `Standard`, `AWS`, `Azure`, `OCI`. |
| subnet info | calculated network facts and usable range details | Strong existing term in the API and frontends. |
| usable addresses | addresses available after reservation rules | Important domain concept. |
| first usable IP | first allocatable host address in the subnet | Important result field. |
| last usable IP | last allocatable host address in the subnet | Important result field. |
| lookup | the frontend's combined query over validation, private-range, Cloudflare, and subnet-info checks | Frontend orchestration term; not a backend domain concept pre-launch. |
| API mediation | policy and forwarding layer in front of the subnet API | Implemented today by the APIM simulator in some paths. |

## Sentiment Analysis Language

| Proposed term | Current meaning in the solution | Aliases or ambiguity |
| --- | --- | --- |
| sentiment | the canonical application name | Keep the shorter name used in URLs such as `sentiment.dev`. |
| comment | the text submitted for analysis | Clear current domain object. |
| sentiment label | the classification result | `positive`, `negative`, or `neutral`. |
| confidence | the certainty score of a classification | Strong existing result term. |
| mixed signals | text containing both positive and negative cues | Present in code as a meaningful rule. |
| classifier | the model that assigns a sentiment label | Current implementation uses an in-process SST classifier. |
| recent comments | the query/read model of prior classified comments | Currently backed by CSV storage. |
| analysis latency | time spent classifying the comment | Present in the API result and telemetry. |
| warm on start | preloading the classifier during startup | Technical, but meaningful within this bounded context. |

## Resolved Questions

These were open for a while. They are resolved here so the pre-launch
vocabulary is stable.

- `lookup` is a **frontend orchestration term**, not a domain term. It is
  the React client's name for the composed call over validation,
  private-range classification, Cloudflare membership, and subnet info. The
  backend does not need a `lookup` endpoint to ship. Revisit post-launch if
  an additive `/lookup` endpoint earns its place.
- `target` stays a **Makefile and workflow noun**. `variant` stays the DDD
  taxonomy term. They coexist: `target` describes what `make` invokes,
  `variant` describes what the operator is running. No rename pre-launch.
- `host access path` is kept as a **documentation umbrella** for the mix of
  `proxy`, `port-forward`, and `host forwards`. It does not replace those
  terms in Makefiles, scripts, or status output. Use it only when explaining
  the concept across variants.
