# SSO Triage Notes (Dex + oauth2-proxy + Gateway API)

This doc captures a practical "debug loop" for when Dex SSO was working and then "something changed".

Scope: kind-local cluster with:

- Dex (IdP)
- oauth2-proxy in front of UIs
- Gateway API `HTTPRoute` objects routing hostnames to the oauth2-proxy services
- Admin UIs: Gitea, ArgoCD, Hubble, SigNoz
- Example app: subnetcalc (static frontend + API behind a router)

## Mental model (keep this in your head)

1. Browser hits `https://<app>.127.0.0.1.sslip.io/...`
2. `HTTPRoute` sends **all paths** for that hostname to an oauth2-proxy `Service` (usually in `sso`)
3. oauth2-proxy either:
   - redirects to Dex (no session), or
   - forwards to its configured `--upstream` (session ok), optionally injecting headers
4. Some apps have an additional "bridge" upstream (e.g. SigNoz auth proxy) to translate OIDC into app-native auth.

When behavior is weird, identify which hop is misconfigured:

- Route points to wrong backend service
- oauth2-proxy args wrong (cookie domain/name, redirect URL, upstream, email-domain, skip-auth-regex)
- ArgoCD Application overrides the Helm values (parameters can silently override values)
- Upstream app expects different auth headers / tokens than oauth2-proxy is sending

## Fast triage checklist

### 1) Confirm routes point to the right backend

If the route points directly to the app (instead of oauth2-proxy), you'll bypass SSO entirely.

Commands:

```bash
kubectl -n gateway-routes get httproute -o wide
kubectl -n gateway-routes get httproute -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.hostnames[*]}{.}{" "}{end}{"\t"}{range .spec.rules[*].backendRefs[*]}{.namespace}{"/"}{.name}{":"}{.port}{" "}{end}{"\n"}{end}'
```

Expected: for each admin hostname, backend should be `sso/oauth2-proxy-<app>:80`.

### 2) Inspect oauth2-proxy args (the load-bearing bits)

The following flags are the usual "one wrong value breaks everything" set:

- `--redirect-url` (must match hostname and `/oauth2/callback`)
- `--cookie-name` + `--cookie-domain` (must match the host you browse)
- `--email-domain` (allowlist; should match the Dex user's email domain)
- `--upstream` (where the UI actually is)
- `--skip-auth-regex` (paths that bypass auth; a common footgun)
- `--set-authorization-header` (can break apps if it overwrites Authorization)
- `--pass-access-token`, `--set-xauthrequest`, `--pass-user-headers` (controls which headers reach upstream)

Commands:

```bash
kubectl -n sso get deploy -o name | grep oauth2-proxy
kubectl -n sso get deploy oauth2-proxy-subnetcalc-uat -o yaml | sed -n '1,220p'
```

### 3) Do "in-cluster curl" tests to isolate gateway vs service behavior

Using a one-off curl pod avoids local DNS/cert/port-forward issues.

Examples:

```bash
# Does oauth2-proxy redirect to Dex when unauthenticated?
kubectl -n default run curltest --rm -i --restart=Never --image=curlimages/curl:8.7.1 -- \
  sh -lc "curl -sS -D - -o /dev/null -H 'Host: subnetcalc.uat.127.0.0.1.sslip.io' http://oauth2-proxy-subnetcalc-uat.sso.svc.cluster.local:80/ | sed -n '1,30p'"

# Does sign-out clear cookies and redirect to /logged-out.html?
kubectl -n default run curltest --rm -i --restart=Never --image=curlimages/curl:8.7.1 -- \
  sh -lc "curl -sS -D - -o /dev/null -H 'Host: subnetcalc.uat.127.0.0.1.sslip.io' 'http://oauth2-proxy-subnetcalc-uat.sso.svc.cluster.local:80/oauth2/sign_out?rd=/logged-out.html' | sed -n '1,40p'"
```

### 4) Subnetcalc-specific: beware `skip-auth-regex` letting `/.auth/*` go "half-authenticated"

Subnetcalc's router provides AppService-style endpoints:

- `/.auth/me` (whoami; frontend uses it to display login state)
- `/.auth/login/...` (redirect to oauth2-proxy start)
- `/.auth/logout` (redirect to oauth2-proxy sign_out and then `/logged-out.html`)

Footgun:

If oauth2-proxy is configured with `--skip-auth-regex` that includes `/.auth/*`, then:

- oauth2-proxy will forward `/.auth/me` without requiring a session
- the router will respond with "no user" (because oauth2-proxy didn't inject headers)
- the frontend can look logged-out while still being able to load, and may send bad/empty `Authorization` headers to `/api`

Fix direction:

- Avoid skipping `/.auth/*` (or implement a real `auth_request` flow for those endpoints).
- Keep `logged-out.html` unauthenticated so you can see the post-logout landing page.

Logout sanity check:

- oauth2-proxy only emits a `Set-Cookie: <cookie>=; Max-Age=0` when the request includes the session cookie.
- If you hit `/oauth2/sign_out` without a cookie, you'll still get redirected, but the browser cookie won't be cleared.

Quick check:

```bash
curl -skD - -o /dev/null 'https://subnetcalc.dev.127.0.0.1.sslip.io/oauth2/sign_out?rd=/logged-out.html' | rg -n 'set-cookie|location'
curl -skD - -o /dev/null -H 'Cookie: kind-sso-dev=foo' 'https://subnetcalc.dev.127.0.0.1.sslip.io/oauth2/sign_out?rd=/logged-out.html' | rg -n 'set-cookie|location'
```

### 5) SigNoz-specific: oauth2-proxy Authorization header + upstream choice

In this setup, SigNoz is typically fronted by a small auth-bridge service (`signoz-auth-proxy`) that:

- logs into SigNoz via `/api/v1/login`
- injects `AUTH_TOKEN` (etc) into the frontend bundle response
- proxies requests to SigNoz with SigNoz's own JWT

Note: because SigNoz is authenticated via a service-user JWT, the email SigNoz shows in its UI can reflect that service user.

### 6) Gitea-specific: forced "Change Password" after SSO

Symptom: after authenticating via Dex, Gitea immediately lands on:

- `/user/settings/change_password`

Most common cause: the Gitea user was created with the `must_change_password` flag set (often happens when bootstrapping users via the admin API with a default password).

Fast fix (in-cluster):

```bash
kubectl -n gitea exec deploy/gitea -c gitea -- gitea admin user must-change-password demo-admin-local --unset
```

Bootstrap fix (this repo):

- `terraform/kubernetes/scripts/ensure-gitea-org.sh` creates users with `must_change_password: false`
- `terraform/kubernetes/scripts/unset-gitea-must-change-password.sh` clears the flag for all users (belt-and-suspenders for local dev)
In this repo we rewrite the `/api/v1/user` response in `signoz-auth-proxy` to prefer the upstream OIDC email forwarded by oauth2-proxy
(`X-Auth-Request-Email` / `X-Forwarded-Email`) so the UI matches the Dex identity.

Common failure modes:

1) oauth2-proxy is pointing upstream directly to `signoz:8080` instead of `signoz-auth-proxy:3000`.
   - Symptom: Dex login works, but SigNoz still shows its own login screen or "apps" UI is broken.

2) oauth2-proxy is configured to set an `Authorization: Bearer <OIDC access token>` header.
   - Symptom: Signoz auth proxy receives the wrong Authorization header and SigNoz API calls break.
   - Fix: do not set Authorization at oauth2-proxy, and/or have signoz-auth-proxy strip inbound Authorization headers.

Safety note: avoid dumping SigNoz JS bundles that include injected JWTs into logs.

### 6) ArgoCD gotcha: Helm `parameters` can override your Helm `values`

Even if `spec.source.helm.values` looks correct, `spec.source.helm.parameters` can silently override it.

Command:

```bash
kubectl -n argocd get application oauth2-proxy-signoz -o jsonpath='{.spec.source.helm.parameters}{"\n"}'
```

If you see something like:

```json
[{"name":"extraArgs.upstream","value":"http://signoz.observability.svc.cluster.local:8080"}]
```

...then your `values` file upstream is being overridden.

If Argo CD isn't picking up the latest commit from the repo quickly enough, you can force a refresh:

```bash
kubectl -n argocd annotate application platform-gateway-routes argocd.argoproj.io/refresh=hard --overwrite
```

### 7) Logs to grab (in order)

```bash
kubectl -n sso logs deploy/dex --tail=200
kubectl -n sso logs deploy/oauth2-proxy-gitea --tail=200
kubectl -n sso logs deploy/oauth2-proxy-signoz --tail=200
kubectl -n observability logs deploy/signoz-auth-proxy --tail=200
```

## Handy automation

See `terraform/kubernetes/scripts/triage-sso.sh`.

## Extra: debugging 502s (oauth2-proxy upstream timeout) on LLM-backed apps

Symptom (browser): oauth2-proxy "502 Bad Gateway" page with:

- `net/http: timeout awaiting response headers`

Symptom (oauth2-proxy logs): a request (often `POST /api/v1/comments`) takes ~30s and then 502s.

Mental model:

- oauth2-proxy defaults `--upstream-timeout` to `30s`.
- If an upstream endpoint does request-time model download / cold-start (e.g. Ollama pulling a model),
  the first real user request can exceed 30s.
- The correct fix for a "should be interactive" endpoint is usually to remove the long cold-start from
  the request path, not to keep increasing timeouts.

Debug loop:

```bash
# Confirm the timeout in logs (should show ~30s request duration):
kubectl -n sso logs deploy/oauth2-proxy-sentiment-dev --tail=300 | rg -n "timeout awaiting response headers|502|/api/v1/comments"

# Bypass oauth2-proxy to see pure upstream latency (no auth involved):
kubectl -n default run curlsent --rm -i --restart=Never --image=curlimages/curl:8.7.1 -- \
  sh -lc 'curl -sS -o /dev/null -w "%{http_code} %{time_total}\n" -H "Content-Type: application/json" \
    -d "{\"text\":\"hello\"}" http://sentiment-router.sentiment-dev.svc.cluster.local:80/api/v1/comments'
```

Fix direction used in this repo:

- Preload the llama.cpp model into the llama PVC (so first request doesn't block on model download).
  before the main container starts.
- This mirrors the previously-working `pcexperiments-orig` pattern and prevents "first request triggers model download".

Gotcha (UAT namespaces):

- The reusable namespaced `sentiment-*` and `subnetcalc-*` Cilium policies intentionally do not grant `world` egress; only the explicit shared guardrails and namespace-local overrides open external paths.
- That means pods in `sentiment-uat` / `subnetcalc-uat` cannot pull model layers unless you explicitly allow it.
- In this repo we add `allow-sentiment-api-llm-egress` (restricted to `app.kubernetes.io/name=sentiment-api`) to allow
  only sentiment-api pods to talk to the external LLM gateway.

Where to look for evidence:

- `kubectl -n <ns> logs pod/<llama-pod> --tail=200`
- SigNoz logs for `sentiment-api` / `llm` spans (if configured)
