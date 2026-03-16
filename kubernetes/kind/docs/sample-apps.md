# Sample Apps

The demo applications appear from stage `700` onward.

The application source trees live under [apps/README.md](../../../apps/README.md).

For the fuller static architecture and policy-control view, see:

- [`apps-c4.md`](../../../terraform/kubernetes/docs/apps-c4.md) for the Mermaid native C4 architecture model
- [`COMPOSITION.md`](../../../terraform/kubernetes/cluster-policies/COMPOSITION.md)

## Subnetcalc

`subnetcalc` is deliberately split so the frontend never talks to the backend directly. The router sends UI traffic to the frontend and `/api/*` traffic to the APIM simulator, which then forwards to the backend.

With SSO enabled at stage `900`, the path looks like this:

```mermaid
flowchart LR
    user["Browser"] --> sso["oauth2-proxy (SSO)"]
    sso --> router["subnetcalc-router"]
    router --> fe["subnetcalc-frontend"]
    router --> apim["subnetcalc-apim-simulator"]
    apim -. "JWKS / issuer checks" .-> dex["Dex"]
    apim --> api["subnetcalc-api"]
```

Without SSO, remove the `oauth2-proxy` hop and start at `subnetcalc-router`.

The important split is:

- frontend traffic stays on `subnetcalc-frontend`
- API traffic goes through `subnetcalc-apim-simulator`
- the router does not call `subnetcalc-api` directly

That routing is documented in:

- [`subnetcalc-router-nginx` in all.yaml](../../../terraform/kubernetes/apps/workloads/base/all.yaml)
- [`subnetcalc-l7-dev.yaml`](../../../terraform/kubernetes/cluster-policies/cilium/dev/subnetcalc-l7-dev.yaml)
- [`apim/all.yaml`](../../../terraform/kubernetes/apps/apim/all.yaml)

## Sentiment

The `sentiment` demo has the same frontend/router split, but unlike
`subnetcalc` it does not add an APIM hop. The router sends browser routes to
the UI and `/api/*` directly to `sentiment-api`.

With SSO enabled at stage `900`, the shipped kind-stage path looks like this:

```mermaid
flowchart LR
    user["Browser"] --> sso["oauth2-proxy (SSO)"]
    sso --> router["sentiment-router"]
    router --> fe["sentiment-auth-ui"]
    router --> api["sentiment-api"]
    api -. "default in-process inference" .-> sst["SST classifier"]
```

Without SSO, remove the `oauth2-proxy` hop and start at `sentiment-router`.

For the shipped kind stages, the key points are:

- `sentiment-router` talks to `sentiment-auth-ui` and `sentiment-api`, not to an APIM simulator
- `sentiment-api` serves the default SST classifier in-process
- the checked-in kind stage files set `llm_gateway_mode = "disabled"`
- the shared workload config sets `SENTIMENT_BACKEND_MODE = "sst"`

That means the shipped kind path does not require a host-side model endpoint
for sentiment to work.

## Legacy LLM Modes

The repo still keeps two opt-in LLM-backed paths for teams that want them:

```mermaid
flowchart LR
    api["sentiment-api"] --> gateway["llm-gateway"]
    gateway --> litellm["LiteLLM"]
    litellm --> llama["llama.cpp"]
```

Those modes exist in:

- [`llm-litellm.yaml`](../../../terraform/kubernetes/apps/workloads/base/llm-litellm.yaml)
- [`variables.tf`](../../../terraform/kubernetes/variables.tf)

Use:

- `llm_gateway_mode = "direct"` for the legacy host-backed `llm-gateway` path
- `llm_gateway_mode = "litellm"` for the legacy in-cluster `LiteLLM -> llama.cpp` path

Neither mode is the default selected by the checked-in kind stage files for
stages `700`, `800`, and `900`.
