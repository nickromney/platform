# Sentiment Compose Architecture

This document explains how `sentiment-llm` works when run directly from the
compose files in this app directory, without Kubernetes or Terraform.

## Scope

- `compose.yml` is the primary local runtime.
- `compose.tls.yml` is a thin overlay that adds a TLS 1.3 front door.
- The default LLM path is `sentiment-api -> litellm -> llama-cpp`.
- A direct host-backed OpenAI-compatible endpoint is still supported through
  environment overrides.

## Compose Files

| File | Role |
| --- | --- |
| [`compose.yml`](../compose.yml) | Main authenticated local stack: Keycloak, oauth2-proxy, edge router, API, UI, and model path. |
| [`compose.tls.yml`](../compose.tls.yml) | Optional TLS 1.3 overlay in front of `oauth2-proxy`. |

## Important Local Quirk

The local Keycloak realm asset still uses the realm name `subnet-calculator`.
That is not a typo in this document. It is the current checked-in compose
behavior in [`compose.yml`](../compose.yml) and
[`keycloak/realm-export.json`](../keycloak/realm-export.json).

## System Context

```mermaid
flowchart LR
    Browser["Browser"]
    TLS["tls-proxy<br/>compose.tls.yml<br/>8443/8444"]
    OAuth["oauth2-proxy<br/>8304"]
    KC["Keycloak<br/>8300<br/>realm: subnet-calculator"]
    Edge["edge nginx<br/>internal router"]
    UI["sentiment-auth-frontend<br/>static SPA"]
    API["sentiment-api"]
    LiteLLM["litellm"]
    Llama["llama-cpp"]
    HostLLM["Host OpenAI-compatible endpoint<br/>host.docker.internal:12434"]

    Browser -->|"default HTTP"| OAuth
    Browser -->|"optional TLS"| TLS
    TLS --> OAuth
    OAuth <-->|"OIDC login / callback"| KC
    OAuth --> Edge
    Edge -->|" / "| UI
    Edge -->|" /api/* "| API
    API -->|"LLM_GATEWAY_MODE=litellm"| LiteLLM
    LiteLLM -->|"default upstream"| Llama
    API -->|"LLM_GATEWAY_MODE=direct"| HostLLM
    LiteLLM -. "optional overridden upstream" .-> HostLLM
```

## Runtime Slices

- `oauth2-proxy` is the browser-facing gate. It handles login and cookie
  management, then forwards all authenticated traffic upstream.
- `edge` is the internal application router. It sends `/api/*` to
  `sentiment-api` and everything else to the static UI.
- `sentiment-api` owns the LLM mode switch. The browser never chooses the
  model path directly.
- `litellm` is a broker, not the model itself. In the default local setup it
  forwards to `llama-cpp`, but it can also proxy to a host endpoint.

## Backend Mode State Diagram

```mermaid
stateDiagram-v2
    [*] --> ReadEnv

    ReadEnv --> DirectMode: LLM_GATEWAY_MODE=direct
    ReadEnv --> LiteLLMMode: LLM_GATEWAY_MODE=litellm or unset

    state DirectMode {
        [*] --> HostEndpoint
        HostEndpoint: sentiment-api calls\nLLM_BACKEND_BASE_URL directly
    }

    state LiteLLMMode {
        [*] --> Broker
        Broker --> LlamaDefault: default\nLITELLM_UPSTREAM_API_BASE=http://llama-cpp:8080/v1
        Broker --> HostBrokered: overridden\nLITELLM_UPSTREAM_API_BASE=http://host.docker.internal:12434/v1
    }
```

## Authenticated Request Journey

```mermaid
sequenceDiagram
    participant B as Browser
    participant O as oauth2-proxy
    participant K as Keycloak
    participant E as edge
    participant UI as sentiment-auth-frontend
    participant API as sentiment-api
    participant L as litellm
    participant M as llama-cpp

    B->>O: GET /
    O-->>B: Redirect to Keycloak login
    B->>K: Authenticate
    K-->>B: Redirect with auth code
    B->>O: /oauth2/callback
    O->>K: Redeem code and validate user
    O->>E: Forward authenticated request
    E->>UI: Serve SPA assets

    B->>O: GET /api/...
    O->>E: Forward authenticated API request
    E->>API: Route /api/*
    API->>L: Classify sentiment
    L->>M: OpenAI-compatible inference request
    M-->>L: Model response
    L-->>API: Brokered response
    API-->>B: JSON result
```

## TLS Overlay

```mermaid
flowchart LR
    Browser["Browser"]
    TLS["tls-proxy<br/>8443 / 8444"]
    OAuth["oauth2-proxy<br/>4180 internal"]
    Edge["edge nginx"]
    App["UI + API path"]

    Browser -->|"HTTPS 8443"| TLS
    Browser -->|"HTTP 8444"| TLS
    TLS -->|"HTTP upstream"| OAuth
    OAuth --> Edge
    Edge --> App
```

## Request Ownership Cheatsheet

| Hop | Owner in compose runtime | Why it exists |
| --- | --- | --- |
| Browser -> `oauth2-proxy` | OIDC front door | Forces login before the app is reachable. |
| `oauth2-proxy` -> `keycloak` | Identity provider | Handles the local OIDC flow. |
| `oauth2-proxy` -> `edge` | Authenticated upstream | Keeps auth separate from the app router. |
| `edge` -> `sentiment-auth-frontend` | UI split | Static assets and API stay separate. |
| `edge` -> `sentiment-api` | API split | `/api/*` stays on the backend path. |
| `sentiment-api` -> `litellm` -> `llama-cpp` | Default inference path | Fully local and self-contained. |
| `sentiment-api` -> host LLM | Optional direct mode | Useful when testing a host-backed model runner. |

## Practical Reading Guide

- Use the system context diagram when you want to know which containers matter.
- Use the state diagram when you want to know which LLM path is active.
- Use the sequence diagram when debugging auth, routing, or upstream latency.
