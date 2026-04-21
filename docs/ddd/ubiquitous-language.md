# Ubiquitous Language

This is the canonical vocabulary for the repo.

It is split into two layers:

- the current implementation and test language
- the domain language that the code should converge on

The goal is to **keep the code and the glossary consistent**. Where they still
diverge, the gap is tracked in
[consistency-plan.md](./consistency-plan.md) with an explicit direction of
travel.

Wire-visible contracts stay frozen until a planned version bump — see
[contracts.md](./contracts.md) for the breaking-change surfaces.

## Translation From Legacy Test And Operator Dialect

These terms are being transitioned out of the codebase in favor of the ratified
domain language.

| Legacy term | Ratified meaning | Notes |
| --- | --- | --- |
| active variant surface | active variant | Renamed to `active variant` in `platform status` and TUI. |
| active variant path | active variant path | Used in machine-ownership checks such as `kubernetes/kind` or `kubernetes/lima`. |
| claimed by | ownership | Expresses which variant currently owns the shared ingress surface. |
| shared host ports | shared host ports | Useful operational concept for the local edge resource. |
| blocked | blocker | A safety precondition failed and operation should not continue. |
| prereqs | readiness | Exposed alongside new `readiness` targets in Makefiles. |
| check-health | readiness | Exposed alongside new `readiness` targets in Makefiles. |
| stage | stage | The cumulative build ladder (100-900). |
| stack | stack | Narrowed to the whole collection of apps realized for a solution variant. |
| status | ownership and readiness | Snapshot of variant state. |

## Ratified Terms

| Term | Current meaning in the solution | Aliases or ambiguity |
| --- | --- | --- |
| platform | the repo/theme word for patterns that platform engineers may reuse | Useful broad label, but not a sharp path taxonomy term. |
| solution | the first-level grouping such as `kubernetes` or `sd-wan` | The repo is grouped by what you want to run. |
| variant | the concrete operable path beneath a solution | Examples: `kubernetes/kind`, `kubernetes/lima`, `kubernetes/slicer`. |
| target | a Makefile and workflow noun | Implementation-facing term for `make` goals. |
| stack | the whole collection of apps realized for a solution variant | A full deployment shape. |
| stage | the cumulative build ladder on a solution variant | Examples: `100` through `900`. |
| provider | reserved for Terraform provider discussions | Not used for `kind`, `lima`, or `slicer`. |
| environment | the app exposure or testing band | Examples: `dev`, `sit`, `uat`, `admin`. |
| workload | a deployed app unit or image | Platform-facing language. |
| readiness | whether a variant can be safely operated or verified now | Implemented via `readiness` Makefile targets and status JSON. |
| blocker | a concrete reason an operation should stop | Technical debt or safety gate. |
| ownership | which variant currently owns shared local ingress | Expressed in `platform status` output. |

## Ratified Stage Labels

| Stage | Label | Notes |
| --- | --- | --- |
| `100` | cluster available | Infrastructure-as-code outcome. |
| `200` | Cilium | Networking layer. |
| `300` | Hubble | Observability/visibility layer. |
| `400` | Argo CD | GitOps controller. |
| `500` | Gitea | Internal Git provider. |
| `600` | policies | Admission and security policies. |
| `700` | app repos | Application source and deployment manifests. |
| `800` | observability | Gateway TLS, monitoring, and dashboards. |
| `900` | SSO | Identity and access proxying. |

## Identity And Access Language

| Term | Meaning in the solution | Aliases or ambiguity |
| --- | --- | --- |
| identity service | the system that authenticates the user | Implemented by Dex or Keycloak. |
| `oauth2-proxy` | the browser-facing auth front door | Handles OIDC flow and session cookies. |
| SSO | authenticated entry through OIDC plus session cookies | Unified authentication strategy. |
| realm | identity namespace | Keycloak/OIDC grouping (e.g., `sentiment`, `subnetcalc`). |
| auth method | the backend auth strategy | `none, api_key, jwt, azure_swa, apim, azure_ad`. |
| session | authenticated browser state | Managed by cookies. |
| user info | authenticated user payload passed downstream | Found in `/oauth2/userinfo` or headers. |
| login | begin an authenticated session | Starts the OIDC flow. |
| logout | end the current session | Clears cookies and session state. |
| Easy Auth | platform-managed auth flow | Azure-specific term used in Static Web Apps. |

## Subnet Analysis Language

| Term | Meaning in the solution | Aliases or ambiguity |
| --- | --- | --- |
| subnetcalc | the network-analysis application name | The product name for the `apps/subnetcalc` suite. |
| address | a single IPv4 or IPv6 address | IP address under analysis. |
| network | a CIDR block under analysis | CIDR notation. |
| CIDR | network notation such as `192.168.1.0/24` | Domain standard. |
| validation | checking that an address or network is well formed | Initial API gate. |
| private range | RFC1918 address space | Private IPv4 space. |
| shared address space | RFC6598 range | CGNAT/Shared space. |
| Cloudflare range check | Cloudflare IP membership | Membership in Cloudflare-owned ranges. |
| cloud mode | reservation rules for a target cloud | `Standard, AWS, Azure, OCI`. |
| subnet info | calculated network facts | Result of the analysis. |
| usable addresses | addresses available after reservation rules | Allocatable hosts. |
| first usable IP | first allocatable host address | Start of usable range. |
| last usable IP | last allocatable host address | End of usable range. |
| lookup | frontend composed query | Client-side orchestration term. |
| API mediation | policy and forwarding layer | Implemented by APIM or simulators. |

## Sentiment Analysis Language

| Term | Meaning in the solution | Aliases or ambiguity |
| --- | --- | --- |
| sentiment | the sentiment-analysis application name | The product name for the `apps/sentiment` suite. |
| comment | the text submitted for analysis | Primary domain object. |
| sentiment label | the classification result | `positive, negative, neutral`. |
| confidence | certainty score | Numerical classification certainty. |
| mixed signals | text with conflicting cues | Specific classification state. |
| classifier | the classification model | SST-based analysis engine. |
| recent comments | the query/read model | Log of prior classifications. |
| analysis latency | classification time | Telemetry field. |
| warm on start | preloading the classifier | Readiness state. |

## Resolved Questions

These were open for a while. They are resolved here so the pre-launch
vocabulary is stable.

- `lookup` is a **frontend orchestration term**, not a domain term. It is
  the React client's name for the composed call over validation,
  private-range classification, Cloudflare membership, and subnet info. The
  backend does not need a `lookup` endpoint to ship.
- `target` stays a **Makefile and workflow noun**. `variant` is the DDD
  taxonomy term. They coexist: `target` describes what `make` invokes,
  `variant` describes what the operator is running.
- `host access path` is the **documentation umbrella** for the mix of
  `proxy`, `port-forward`, and `host forwards`. It does not replace those
  terms in Makefiles, scripts, or status output.
