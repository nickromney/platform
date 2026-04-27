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
| solution | the first-level grouping, currently `kubernetes` | The repo is grouped by what you want to run. |
| variant | the concrete operable path beneath a solution | Examples: `kubernetes/kind`, `kubernetes/lima`, `kubernetes/slicer`. |
| target | a Makefile and workflow noun | Implementation-facing term for `make` goals. |
| stack | the whole collection of apps realized for a solution variant | A full deployment shape. |
| stage | the cumulative build ladder on a solution variant | Examples: `100` through `900`. |
| provider | reserved for Terraform provider discussions | Not used for `kind`, `lima`, or `slicer`. |
| environment | the app exposure or testing band | Examples: `dev`, `sit`, `uat`, `admin`. |
| environment namespace | a Kubernetes namespace carrying an environment label | Current application environments are `dev`, `sit`, and `uat`; `admin` is a route band rather than an app namespace. |
| namespace role | platform boundary label for policy inheritance | Current values are `application`, `shared`, and `platform`. |
| workload | a deployed app unit or image | Platform-facing language. |
| application spec | the source-of-truth intent for a shipped app surface | Currently spread across Terraform locals, Argo CD app manifests, seeded GitOps paths, route hostnames, and image inputs. |
| application catalog | the operator-visible list of platform and app surfaces | Currently realized by Argo CD app names and the Grafana Launchpad tile inventory. |
| deployment read model | the query-side view of rollout health | Built from Kubernetes deployment readiness, Argo CD sync/health, Prometheus metrics, and status helpers. |
| readiness | whether a variant can be safely operated or verified now | Implemented via `readiness` Makefile targets and status JSON. |
| blocker | a concrete reason an operation should stop | Technical debt or safety gate. |
| ownership | which variant currently owns shared local ingress | Expressed in `platform status` output. |
| portal surface | browser-facing navigation or admin UI for platform operators | Current examples: Grafana Launchpad, Argo CD, Headlamp, Gitea, Keycloak, Hubble, and Policy Reporter. |
| status surface | CLI or dashboard view that summarizes current state | Current examples: `platform status`, variant `status` targets, Argo CD Applications, and Grafana Launchpad health tiles. |

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
| identity provider | the selected OIDC authority for stage `900` | `sso_provider` selects `dex` or `keycloak`; local stage `900` paths now select Keycloak. |
| `oauth2-proxy` | the browser-facing auth front door | Handles OIDC flow and session cookies. |
| SSO session store | internal server-side session cache for `oauth2-proxy` | Stage `900` uses Redis-compatible storage so Keycloak tokens are not carried as oversized browser cookies. |
| SSO | authenticated entry through OIDC plus session cookies | Unified authentication strategy. |
| realm | identity namespace | Keycloak/OIDC grouping (e.g., `sentiment`, `subnetcalc`). |
| client | OIDC relying party registered with the identity provider | Current clients include `oauth2-proxy`, `argocd`, `headlamp`, and the `apim-simulator` resource client. |
| resource audience | token audience for an API or mediation layer that consumes bearer tokens | Stage `900` uses `apim-simulator` so APIM validates API tokens separately from the `oauth2-proxy` browser client. |
| group claim | token/userinfo field carrying user groups | Current claim name is `groups`. |
| platform role group | identity group mapped to platform tool authorization | Current groups are `platform-admins` and `platform-viewers`. |
| application access group | identity group scoped to an app/environment pair | Current examples: `app-subnetcalc-dev`, `app-subnetcalc-uat`, `app-sentiment-dev`, `app-sentiment-uat`, `app-hello-platform-dev`, `app-hello-platform-uat`. |
| RBAC mapping | translation from identity groups into product permissions | Argo CD maps platform groups to admin/read-only roles; Kubernetes RBAC checks use the OIDC group claim. |
| auth method | the backend auth strategy | `none, api_key, jwt, azure_swa, apim, azure_ad`. |
| session | authenticated browser state | Managed by secure browser cookies plus the SSO session store for Keycloak-backed Kubernetes paths. |
| user info | authenticated user payload passed downstream | Found in `/oauth2/userinfo` or headers. |
| login | begin an authenticated session | Starts the OIDC flow. |
| logout | end the current session | Clears cookies and session state. |
| generated secret | credential material generated during stack apply | Current examples: OIDC client secrets, `oauth2-proxy` cookie secret, and Keycloak Postgres password. |
| imported secret | credential material supplied from operator input | Current example: demo user password from `gitea_member_user_pwd` / `PLATFORM_DEMO_PASSWORD`. |
| secret projection | mounting or referencing a Kubernetes Secret into a workload | Used for OIDC clients, Keycloak admin/Postgres credentials, registry credentials, and mkcert CA trust. |
| secret rotation | replacing credential material and reconciling consumers | Not a separate domain workflow yet; current rotation is Terraform/apply-driven replacement. |
| Easy Auth | platform-managed auth flow | Azure-specific term used in Static Web Apps. |

## Application And Environment Language

The platform now has a first-class service catalog at
`catalog/platform-apps.json`. Treat that file as the source of intent for
application ownership, environments, app/environment RBAC, secret bindings,
deployment evidence, and scorecards. Current app/environment surfaces include
`hello-platform-dev`, `hello-platform-uat`, `sentiment-dev`, `sentiment-uat`,
`subnetcalc-dev`, and `subnetcalc-uat`.

| Term | Meaning in the solution | Aliases or ambiguity |
| --- | --- | --- |
| service catalog | first-class inventory of platform applications and their environment intent | Implemented as `catalog/platform-apps.json`; older docs may say application catalog. |
| application spec | catalog entry for one workload, owner, environments, deployment evidence, secrets, and scorecard | Not the same as a Kubernetes Deployment. |
| environment request | operator self-service request to create or inspect an app environment | Rendered by `idp-environment.sh`; current output lives under `.run/idp`. |
| deployment record | read-side evidence of what is deployed where | Includes Argo CD app names, GitOps paths, image tags, and public URLs. |
| secret binding | declared relationship between a workload and secret material it needs | Documents generated or imported secrets without publishing values. |
| scorecard | lightweight readiness/security evidence attached to a catalog app | Current scorecards are source-controlled metadata, not a separate scoring service. |
| app/environment RBAC | group-scoped authorization for a specific app in a specific environment | Implemented with groups such as `app-hello-platform-dev`; distinct from org-level platform roles. |
| portable auth mode | app-level authentication mode that does not require the local Keycloak realm | `subnetcalc` retains `none`, `jwt`, `azure_swa`, `apim`, and OIDC configuration knobs for non-kind platforms. |

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
