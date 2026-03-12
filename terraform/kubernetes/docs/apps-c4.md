# Sentiment And Subnetcalc C4 Model

This document is a static reasoning aid for the two demo applications and the
policies that constrain them. It complements Hubble and the Cilium UI by
showing the intended design before traffic is observed.

Scope:

- stage `900` style flow, with SSO enabled
- current shipped kind default for sentiment: direct host-backed LLM mode
- both `dev` and `uat`, with the key intentional split called out explicitly

## Reading Guide

- The diagrams use Mermaid's native C4 beta syntax so they render in-repo as
  actual C4 views, not flowcharts pretending to be C4.
- Edge labels call out the main controller for the hop: Cilium policy, app
  config, or application fallback logic.
- `dev` and `uat` usually share the same request path; the Cloudflare live
  fetch is the main deliberate exception.
- The C4 views show structure and control boundaries; the sequence diagrams
  later in the document show handshake and request-flow behavior.
- Dynamic C4 views are split into focused paths because Mermaid C4 beta is much
  better at ordered interactions than at `alt` / `else` branching.

## System Context

```mermaid
%%{init: {"theme": "base", "themeVariables": {"background": "#ffffff"}}}%%
C4Context
    title Sentiment and Subnetcalc system context

    Person(browser, "Browser", "Interactive user agent")
    System_Ext(cloudflare, "www.cloudflare.com", "Serves the live Cloudflare range files")
    System_Ext(host_llm, "Host-side LLM endpoint", "Docker Desktop model runner on TCP 12434")

    Enterprise_Boundary(platform, "Local platform demo") {
        System(gateway, "platform-gateway", "Cluster entrypoint and shared routing")
        System(sso, "SSO stack", "oauth2-proxy and Dex")
        System(subnetcalc, "subnetcalc", "Authenticated CIDR and Cloudflare range demo")
        System(sentiment, "sentiment", "Authenticated sentiment analysis demo")
        System(observability, "otel-collector", "Shared telemetry sink")
    }

    Rel(browser, gateway, "Uses over HTTPS")
    Rel(gateway, sso, "Routes authenticated traffic through")
    Rel(sso, subnetcalc, "Forwards subnetcalc requests to")
    Rel(sso, sentiment, "Forwards sentiment requests to")
    Rel(subnetcalc, observability, "Exports traces to")
    Rel(sentiment, observability, "Exports traces to")
    Rel(subnetcalc, cloudflare, "dev only: fetches live range files from")
    Rel(sentiment, host_llm, "direct mode: calls through llm-gateway to")
    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

## Container View

### Subnetcalc

```mermaid
%%{init: {"theme": "base", "themeVariables": {"background": "#ffffff"}}}%%
C4Container
    title Subnetcalc container view

    Person(browser, "Browser", "Interactive user agent")
    Container_Ext(gateway, "platform-gateway", "Ingress / reverse proxy", "Cluster entrypoint for the demo hosts")
    Container_Ext(oauth, "oauth2-proxy", "OAuth2 reverse proxy", "Applies login and session checks for subnetcalc")
    Container_Ext(dex, "Dex", "OIDC provider", "Publishes issuer and JWKS metadata")
    Container_Ext(otel, "otel-collector", "OpenTelemetry Collector", "Receives traces from the app")
    Container_Ext(cloudflare, "www.cloudflare.com", "HTTPS endpoint", "Serves /ips-v4 and /ips-v6")

    Container_Boundary(subnetcalc, "subnetcalc") {
        Container(router, "subnetcalc-router", "NGINX", "Routes browser traffic between frontend and APIM")
        Container(frontend, "subnetcalc-frontend", "SPA", "Browser user interface")
        Container(apim, "subnetcalc-apim-simulator", "APIM simulator", "Validates identity context and forwards /api traffic")
        Container(api, "subnetcalc-api", "FastAPI", "CIDR calculation and Cloudflare range logic")
    }

    Rel(browser, gateway, "Uses over HTTPS")
    Rel(gateway, oauth, "Routes subnetcalc host/path traffic to")
    Rel(oauth, router, "Forwards authenticated traffic to")
    Rel(router, frontend, "Serves UI routes from")
    Rel(router, apim, "Forwards /api/* to")
    Rel(apim, dex, "Validates issuer and JWKS against")
    Rel(apim, api, "Forwards validated API calls to")
    Rel(api, otel, "Exports traces to")
    Rel(api, cloudflare, "dev only: fetches live range files from")
    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

Key intent:

- the router never talks to `subnetcalc-api` directly
- `/api/*` traffic always crosses the APIM simulator first
- only `dev` may fetch live Cloudflare range files; `uat` falls back in code

### Sentiment

```mermaid
%%{init: {"theme": "base", "themeVariables": {"background": "#ffffff"}}}%%
C4Container
    title Sentiment container view

    Person(browser, "Browser", "Interactive user agent")
    Container_Ext(gateway, "platform-gateway", "Ingress / reverse proxy", "Cluster entrypoint for the demo hosts")
    Container_Ext(oauth, "oauth2-proxy", "OAuth2 reverse proxy", "Applies login and session checks for sentiment")
    Container_Ext(otel, "otel-collector", "OpenTelemetry Collector", "Receives traces from the app")
    Container_Ext(llm_gateway, "llm-gateway", "ExternalName Service", "Stable in-cluster name for the host-backed LLM")
    Container_Ext(host_llm, "Host-side LLM endpoint", "Docker Desktop model runner", "Listens on TCP 12434")

    Container_Boundary(sentiment, "sentiment") {
        Container(router, "sentiment-router", "NGINX", "Routes browser traffic between UI and API")
        Container(ui, "sentiment-auth-ui", "SPA", "Browser user interface")
        Container(api, "sentiment-api", "API service", "Calls the configured LLM backend and emits traces")
    }

    Container_Boundary(sentiment_alt, "Alternative in-cluster LLM mode") {
        Container(litellm, "litellm", "LiteLLM", "Optional in-cluster LLM gateway")
        Container(llama, "llama.cpp", "llama.cpp server", "Optional in-cluster model runtime")
    }

    Rel(browser, gateway, "Uses over HTTPS")
    Rel(gateway, oauth, "Routes sentiment host/path traffic to")
    Rel(oauth, router, "Forwards authenticated traffic to")
    Rel(router, ui, "Serves UI routes from")
    Rel(router, api, "Forwards /api/* to")
    Rel(api, llm_gateway, "direct mode: calls")
    Rel(llm_gateway, host_llm, "Resolves and connects to")
    Rel(api, litellm, "alternative mode: calls")
    Rel(litellm, llama, "Forwards model requests to")
    Rel(api, otel, "Exports traces to")
    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="2")
```

Key intent:

- the router splits browser traffic between UI and API
- in the shipped kind flow, `sentiment-api` is effectively talking to a
  host-backed endpoint via `llm-gateway`
- the repo still contains a fully in-cluster LiteLLM plus `llama.cpp` mode,
  but that is not the default selected by the checked-in kind stages

## Dynamic Views

### Subnetcalc API Path

```mermaid
%%{init: {"theme": "base", "themeVariables": {"background": "#ffffff"}}}%%
C4Dynamic
    title Subnetcalc API path

    Person(browser, "Browser", "Interactive user agent")
    Container(gateway, "platform-gateway", "Ingress / reverse proxy", "Shared entrypoint")
    Container(oauth, "oauth2-proxy", "OAuth2 reverse proxy", "Subnetcalc auth boundary")
    Container(router, "subnetcalc-router", "NGINX", "Routes UI and API traffic")
    Container(apim, "subnetcalc-apim-simulator", "APIM simulator", "Validates auth context and forwards /api traffic")
    Container(dex, "Dex", "OIDC provider", "Publishes issuer and JWKS metadata")
    Container(api, "subnetcalc-api", "FastAPI", "CIDR calculation and Cloudflare range logic")
    Container(otel, "otel-collector", "OpenTelemetry Collector", "Shared telemetry sink")

    RelIndex(1, browser, gateway, "HTTPS request")
    RelIndex(2, gateway, oauth, "Route to oauth2-proxy")
    RelIndex(3, oauth, router, "Authenticated forward")
    RelIndex(4, router, apim, "Forward /api/*")
    RelIndex(5, apim, dex, "Validate issuer and JWKS")
    RelIndex(6, apim, api, "Forward validated API request")
    RelIndex(7, api, otel, "Emit traces")
    UpdateLayoutConfig($c4ShapeInRow="4", $c4BoundaryInRow="1")
```

Control points:

- `platform-gateway-hardened`, `sso-hardened`, and the environment-specific
  router ingress policies control entry into `subnetcalc`.
- `subnetcalc-router-l7-dev` or `subnetcalc-router-l7-uat` constrains the
  router to APIM hop.
- `subnetcalc-api-l7-dev` or `subnetcalc-api-l7-uat` constrains the APIM to API
  hop.

### Subnetcalc Range Source Split

```mermaid
%%{init: {"theme": "base", "themeVariables": {"background": "#ffffff"}}}%%
C4Dynamic
    title Subnetcalc live range fetch in dev

    Container(api, "subnetcalc-api", "FastAPI", "CIDR calculation and Cloudflare range logic")
    Container_Ext(cloudflare, "www.cloudflare.com", "HTTPS endpoint", "Serves /ips-v4 and /ips-v6")

    RelIndex(1, api, cloudflare, "GET /ips-v4")
    RelIndex(2, api, cloudflare, "GET /ips-v6")
    UpdateLayoutConfig($c4ShapeInRow="2", $c4BoundaryInRow="1")
```

Control points:

- `dev-subnetcalc-api-cloudflare-egress` allows the `dev` live fetch path.
- `uat` has no equivalent allow, so the application falls back in
  `cloudflare_ips.py`.

### Sentiment API Path

```mermaid
%%{init: {"theme": "base", "themeVariables": {"background": "#ffffff"}}}%%
C4Dynamic
    title Sentiment API path in shipped direct mode

    Person(browser, "Browser", "Interactive user agent")
    Container(gateway, "platform-gateway", "Ingress / reverse proxy", "Shared entrypoint")
    Container(oauth, "oauth2-proxy", "OAuth2 reverse proxy", "Sentiment auth boundary")
    Container(router, "sentiment-router", "NGINX", "Routes UI and API traffic")
    Container(api, "sentiment-api", "API service", "Calls the configured LLM backend and emits traces")
    Container(llm_gateway, "llm-gateway", "ExternalName Service", "Stable in-cluster name for the host-backed LLM")
    Container_Ext(host_llm, "Host-side LLM endpoint", "Docker Desktop model runner", "Listens on TCP 12434")
    Container(otel, "otel-collector", "OpenTelemetry Collector", "Shared telemetry sink")

    RelIndex(1, browser, gateway, "HTTPS request")
    RelIndex(2, gateway, oauth, "Route to oauth2-proxy")
    RelIndex(3, oauth, router, "Authenticated forward")
    RelIndex(4, router, api, "Forward /api/*")
    RelIndex(5, api, llm_gateway, "Call llm-gateway")
    RelIndex(6, llm_gateway, host_llm, "Resolve ExternalName and connect on 12434")
    RelIndex(7, api, otel, "Emit traces")
    UpdateLayoutConfig($c4ShapeInRow="4", $c4BoundaryInRow="1")
```

Control points:

- `platform-gateway-hardened`, `sso-hardened`, and the environment-specific
  router ingress policies control entry into `sentiment`.
- `sentiment-router-l7-dev` or `sentiment-router-l7-uat` plus the backend
  ingress policies constrain the router to API hop.
- `allow-sentiment-api-llm-egress` constrains the direct-mode LLM path.

### Sentiment Alternative LLM Path

```mermaid
%%{init: {"theme": "base", "themeVariables": {"background": "#ffffff"}}}%%
C4Dynamic
    title Sentiment alternative in-cluster LLM path

    Container(api, "sentiment-api", "API service", "Calls the configured LLM backend and emits traces")
    Container(litellm, "litellm", "LiteLLM", "Optional in-cluster LLM gateway")
    Container(llama, "llama.cpp", "llama.cpp server", "Optional in-cluster model runtime")

    RelIndex(1, api, litellm, "Call model alias on 4000")
    RelIndex(2, litellm, llama, "Forward to llama.cpp on 8080")
    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

Control points:

- `dev/uat-sentiment-api-egress` allows `sentiment-api` to reach `litellm`.
- `dev/uat-sentiment-litellm-ingress-egress` and
  `dev/uat-sentiment-llama-ingress` constrain the in-cluster LLM path.

## Journey Views

### Subnetcalc Request Journey

```mermaid
%%{init: {"theme": "base", "themeVariables": {"background": "#ffffff"}}}%%
sequenceDiagram
    autonumber
    participant Browser as Browser
    participant Gateway as platform-gateway
    participant OAuth as oauth2-proxy
    participant Router as subnetcalc-router
    participant APIM as subnetcalc-apim-simulator
    participant Dex as Dex
    participant API as subnetcalc-api
    participant OTel as otel-collector

    Browser->>Gateway: HTTPS request
    Gateway->>OAuth: Route to oauth2-proxy
    OAuth->>Router: Authenticated forward
    Note over OAuth,Router: Cilium: platform-gateway-hardened + sso-hardened + dev/uat-subnetcalc-router-ingress

    alt UI path
        Router->>Router: Match non-/api route
        Router->>Browser: SPA content via subnetcalc-frontend
        Note over Router,Browser: Cilium: dev/uat-subnetcalc-frontend-ingress
    else API path
        Router->>APIM: Forward /api/*
        Note over Router,APIM: Cilium: subnetcalc-router-l7-dev or subnetcalc-router-l7-uat
        APIM->>Dex: JWKS / issuer validation
        Note over APIM,Dex: Cilium: apim-baseline + sso-hardened
        APIM->>API: Forward validated API request
        Note over APIM,API: Cilium: subnetcalc-api-l7-dev or subnetcalc-api-l7-uat
        API->>OTel: Emit traces
    end
```

### Subnetcalc Live Range Refresh

```mermaid
%%{init: {"theme": "base", "themeVariables": {"background": "#ffffff"}}}%%
sequenceDiagram
    autonumber
    participant API as subnetcalc-api
    participant Cloudflare as www.cloudflare.com

    alt dev
        API->>Cloudflare: GET /ips-v4 and /ips-v6
        Note over API,Cloudflare: Cilium: dev-subnetcalc-api-cloudflare-egress
        Cloudflare-->>API: Published range files
    else uat
        API->>API: Use bundled fallback ranges
        Note over API: Application code path in [cloudflare_ips.py](../../apps/subnet-calculator/api-fastapi-container-app/app/cloudflare_ips.py)
    end
```

### Subnetcalc Auth Handshake And Logout

```mermaid
%%{init: {"theme": "base", "themeVariables": {"background": "#ffffff"}}}%%
sequenceDiagram
    autonumber
    participant Browser as Browser
    participant Gateway as platform-gateway
    participant OAuth as oauth2-proxy
    participant Dex as Dex
    participant Router as subnetcalc-router

    Browser->>Gateway: GET /
    Gateway->>OAuth: Route host to oauth2-proxy
    OAuth-->>Browser: 302 to Dex via /oauth2/start
    Browser->>Dex: Authenticate
    Dex-->>OAuth: Callback with auth code
    OAuth->>OAuth: Create session cookie
    OAuth->>Router: Forward authenticated request with user headers
    Router-->>Browser: SPA shell
    Browser->>Gateway: GET /.auth/me
    Gateway->>OAuth: Route host to oauth2-proxy
    OAuth->>Router: Forward /.auth/me with auth headers
    Router-->>Browser: Current user payload
    Browser->>Gateway: GET /.auth/logout
    Gateway->>OAuth: Route host to oauth2-proxy
    OAuth->>Router: Forward logout helper path
    Router-->>Browser: 302 /oauth2/sign_out?rd=/logged-out.html
    Browser->>OAuth: GET /oauth2/sign_out with session cookie
    OAuth-->>Browser: Clear cookie and redirect /logged-out.html
```

### Sentiment Request Journey

```mermaid
%%{init: {"theme": "base", "themeVariables": {"background": "#ffffff"}}}%%
sequenceDiagram
    autonumber
    participant Browser as Browser
    participant Gateway as platform-gateway
    participant OAuth as oauth2-proxy
    participant Router as sentiment-router
    participant UI as sentiment-auth-ui
    participant API as sentiment-api
    participant GatewaySvc as llm-gateway Service
    participant HostLLM as Host-side LLM
    participant OTel as otel-collector

    Browser->>Gateway: HTTPS request
    Gateway->>OAuth: Route to oauth2-proxy
    OAuth->>Router: Authenticated forward
    Note over OAuth,Router: Cilium: platform-gateway-hardened + sso-hardened + dev/uat-sentiment-router-ingress

    alt UI path
        Router->>UI: Serve UI route
        Note over Router,UI: Cilium: dev/uat-sentiment-frontend-ingress
    else API path
        Router->>API: Forward /api/*
        Note over Router,API: Cilium: sentiment-router-l7-dev or sentiment-router-l7-uat + dev/uat-sentiment-backend-ingress
        API->>GatewaySvc: Call llm-gateway
        GatewaySvc->>HostLLM: Resolve ExternalName and connect on 12434
        Note over API,HostLLM: Cilium: allow-sentiment-api-llm-egress in direct mode
        API->>OTel: Emit traces
    end
```

## Policy Control Matrix

| Hop | Runtime owner | Main control point | Notes |
| --- | --- | --- | --- |
| `platform-gateway -> oauth2-proxy` | Gateway routing and SSO | `platform-gateway-hardened` and `sso-hardened` | Shared platform boundary for both apps. |
| `oauth2-proxy -> subnetcalc-router` | Authenticated reverse proxy | `sso-hardened` plus `dev-subnetcalc-router-ingress` or `uat-subnetcalc-router-ingress` | Only SSO pods should reach the router. |
| `subnetcalc-router -> subnetcalc-frontend` | Router UI path | `dev-subnetcalc-frontend-ingress` or `uat-subnetcalc-frontend-ingress` | The router stays the only frontend caller. |
| `subnetcalc-router -> subnetcalc-apim-simulator` | Router API path | `subnetcalc-router-l7-dev` or `subnetcalc-router-l7-uat` | L7 policy constrains methods and paths. |
| `subnetcalc-apim-simulator -> subnetcalc-api` | Token-checked API forwarding | `apim-baseline` plus `subnetcalc-api-l7-dev` or `subnetcalc-api-l7-uat` | APIM is the only allowed backend caller. |
| `subnetcalc-api -> www.cloudflare.com` | Background range refresh | `dev-subnetcalc-api-cloudflare-egress` in `dev`; no matching allow in `uat` | `dev` uses live fetch, `uat` uses fallback in code. |
| `oauth2-proxy -> sentiment-router` | Authenticated reverse proxy | `sso-hardened` plus `dev-sentiment-router-ingress` or `uat-sentiment-router-ingress` | Mirrors the subnetcalc entry path. |
| `sentiment-router -> sentiment-auth-ui` | Router UI path | `dev-sentiment-frontend-ingress` or `uat-sentiment-frontend-ingress` | Frontend is isolated behind the router. |
| `sentiment-router -> sentiment-api` | Router API path | `sentiment-router-l7-dev` or `sentiment-router-l7-uat` plus `dev/uat-sentiment-backend-ingress` | UI and API stay separate. |
| `sentiment-api -> llm-gateway -> host LLM` | Direct mode LLM call | `allow-sentiment-api-llm-egress` | The Service is `ExternalName`; the policy is enforced at the API pod. |
| `sentiment-api -> litellm -> llama.cpp` | In-cluster LLM mode | `dev/uat-sentiment-api-egress`, `dev/uat-sentiment-litellm-ingress-egress`, and `dev/uat-sentiment-llama-ingress` | Present in repo, but not the checked-in default kind mode. |
| `sentiment-api` and `subnetcalc-api` -> `otel-collector` | Trace export | `dev/uat-sentiment-api-egress` and `subnetcalc-api-l7-dev` or `subnetcalc-api-l7-uat` | Observability is part of the application path, not an afterthought. |

## Policy Layering Cheatsheet

- `shared/` holds clusterwide baselines and platform boundaries.
- `dev/` and `uat/` hold namespace-specific app entry, app isolation, and
  request-path restrictions.
- Cilium is additive, so the useful mental model is:
  1. shared platform and DNS baselines
  2. environment-specific app ingress and egress
  3. L7 router and API guards where HTTP path control matters
- The composition of those layers is easier to inspect through
  `terraform/kubernetes/scripts/show-policy-composition.sh` and the generated
  `cluster-policies/COMPOSITION.md` view than by reading filenames alone.
