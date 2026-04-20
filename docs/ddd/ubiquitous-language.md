# Working Ubiquitous Language

This is an initial draft extracted from the current solution.

It is intentionally split into two layers:

- the implementation and test language that exists today
- the candidate domain language that seems closer to how a domain expert would
  reason about the solution

The goal is not to freeze current names. The goal is to make the translation
problem visible so the team can agree on better names.

## Translation From Current Test And Operator Dialect

| Current term | Candidate meaning | Notes |
| --- | --- | --- |
| active provider | the active variant currently owning the local stack | In repo terms today this usually means a path such as `kubernetes/kind` or `kubernetes/lima`. `provider` should stay Terraform-specific in the domain language. |
| active project path | the active solution/variant path | Seen in machine-ownership checks such as `kubernetes/kind` or `kubernetes/lima`. |
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
| lookup | the frontend's combined query over validation, private-range, Cloudflare, and subnet-info checks | Useful application term, not yet a clear domain term. |
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

## Remaining Open Questions

- whether `lookup` is a genuine domain term or only a frontend orchestration term
- where the boundary should sit between Makefile `target` language and DDD
  `variant` language
- whether `host access path` is genuinely a better umbrella term than the
  current mix of `proxy`, `port-forward`, and `host forwards`
