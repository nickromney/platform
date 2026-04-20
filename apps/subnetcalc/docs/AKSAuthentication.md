# Authentication Options for Azure Kubernetes Service (AKS)

## Overview

Unlike Azure App Service and Azure Container Apps, **AKS does not have built-in Easy Auth**. Authentication must be implemented using one of several patterns. This document covers the available options for protecting frontend applications in AKS.

## Quick Comparison

| Option | Complexity | Easy Auth-like? | Best For |
|--------|-----------|----------------|----------|
| **OAuth2 Proxy Sidecar** | Low-Medium | Yes | Most use cases, closest to Easy Auth |
| **Cilium + OAuth2 Proxy** | Medium | Yes | If already using Cilium CNI |
| **Service Mesh (Istio/Linkerd)** | High | Partial | Enterprise with existing mesh |
| **Application Gateway + APIM** | Medium | No | API-first architectures |
| **Client-Side SPA Auth** | Low | No | Simple apps, no forced login |
| **Azure Container Apps** | Low | Yes | Alternative to AKS if Easy Auth needed |

## Option 1: OAuth2 Proxy Sidecar (Recommended)

OAuth2 Proxy is an open-source reverse proxy that provides Easy Auth-like functionality in Kubernetes.

### Architecture

```text
User Request
    ↓
Ingress (nginx/cilium)
    ↓
Pod:
  ├─ OAuth2 Proxy :4180 (authentication sidecar)
  │    ↓ (checks auth, redirects if needed)
  │    ↓ (OAuth flow with Entra ID)
  │    ↓ (sets cookie)
  └─ Frontend :80 (nginx serving React)
       ↓ (API calls)
App Gateway → APIM → Backend
```

### Deployment

#### 1. Basic Pod Configuration

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  containers:
  # OAuth2 Proxy sidecar - handles authentication
  - name: oauth2-proxy
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
    args:
    # Provider configuration
    - --provider=oidc
    - --oidc-issuer-url=https://login.microsoftonline.com/$(TENANT_ID)/v2.0
    - --client-id=$(CLIENT_ID)
    - --client-secret=$(CLIENT_SECRET)
    - --cookie-secret=$(COOKIE_SECRET)

    # Redirect configuration
    - --redirect-url=https://myapp.example.com/oauth2/callback

    # Upstream (where to proxy authenticated requests)
    - --upstream=http://localhost:80

    # Listen address
    - --http-address=0.0.0.0:4180

    # Authentication settings
    - --email-domain=*
    - --cookie-secure=true
    - --cookie-httponly=true
    - --cookie-expire=4h
    - --cookie-refresh=1h

    # OIDC scopes
    - --scope=openid profile email

    # Pass authentication headers to upstream
    - --pass-authorization-header=true
    - --pass-access-token=true
    - --pass-user-headers=true
    - --set-authorization-header=true
    - --set-xauthrequest=true

    env:
    - name: TENANT_ID
      valueFrom:
        secretKeyRef:
          name: auth-config
          key: tenant-id
    - name: CLIENT_ID
      valueFrom:
        secretKeyRef:
          name: auth-config
          key: client-id
    - name: CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: auth-config
          key: client-secret
    - name: COOKIE_SECRET
      valueFrom:
        secretKeyRef:
          name: auth-config
          key: cookie-secret

    ports:
    - containerPort: 4180
      name: proxy
      protocol: TCP

    livenessProbe:
      httpGet:
        path: /ping
        port: 4180
      initialDelaySeconds: 10
      periodSeconds: 10

    readinessProbe:
      httpGet:
        path: /ping
        port: 4180
      initialDelaySeconds: 5
      periodSeconds: 5

  # Frontend container - serves static files
  - name: nginx
    image: myregistry.azurecr.io/frontend:latest
    ports:
    - containerPort: 80
      name: http
      protocol: TCP

    livenessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 10
      periodSeconds: 10

    readinessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
```

#### 2. Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: auth-config
type: Opaque
stringData:
  tenant-id: "your-tenant-id"
  client-id: "your-client-id"
  client-secret: "your-client-secret"
  # Generate with: python -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())'
  cookie-secret: "base64-encoded-32-byte-string"
```

#### 3. Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  selector:
    app: frontend
  ports:
  - name: proxy
    port: 4180
    targetPort: 4180
    protocol: TCP
  type: ClusterIP
```

#### 4. Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.example.com
    secretName: frontend-tls
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 4180  # Route to OAuth2 Proxy, not nginx
```

### Using Helm Chart

OAuth2 Proxy has an official Helm chart for easier deployment:

```bash
# Add repo
helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
helm repo update

# Install
helm install oauth2-proxy oauth2-proxy/oauth2-proxy \
  --set config.clientID="your-client-id" \
  --set config.clientSecret="your-client-secret" \
  --set config.cookieSecret="$(openssl rand -base64 32 | head -c 32)" \
  --set config.configFile="provider=oidc
oidc_issuer_url=https://login.microsoftonline.com/tenant-id/v2.0
email_domains=*
upstreams=http://frontend:80
redirect_url=https://myapp.example.com/oauth2/callback"
```

### Headers Forwarded to Upstream

OAuth2 Proxy forwards these headers to your frontend (similar to Easy Auth):

- `X-Auth-Request-User` - User's email/username
- `X-Auth-Request-Email` - User's email
- `X-Auth-Request-Preferred-Username` - User's preferred username
- `X-Auth-Request-Groups` - User's groups (if configured)
- `X-Auth-Request-Access-Token` - Access token (if `--pass-access-token=true`)
- `Authorization: Bearer <token>` - JWT token (if `--set-authorization-header=true`)

## Option 2: Cilium + OAuth2 Proxy

If you're using Cilium as your CNI, combine it with OAuth2 Proxy for enhanced security.

### Architecture

```text
User Request
    ↓
Cilium Ingress (L7 policy enforcement)
    ↓
Pod:
  ├─ OAuth2 Proxy :4180 (authentication)
  └─ Frontend :80 (nginx)
       ↓ (API calls)
Cilium Network Policy (enforces mTLS, L7 rules)
    ↓
APIM → Backend
```

### Deployment

**1. OAuth2 Proxy Deployment** (same as Option 1)

#### 2. Cilium Network Policy

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: frontend-ingress-policy
spec:
  endpointSelector:
    matchLabels:
      app: frontend
  ingress:
  # Only allow ingress traffic from Cilium Ingress or specific namespace
  - fromEndpoints:
    - matchLabels:
        io.cilium.k8s.policy.serviceaccount: cilium-ingress
    toPorts:
    - ports:
      - port: "4180"
        protocol: TCP
      rules:
        http:
        - method: "GET"
        - method: "POST"
          path: "/oauth2/callback"
        - method: "GET"
          path: "/oauth2/sign_in"
```

#### 3. L7 Policy for API Calls

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: frontend-to-api-policy
spec:
  endpointSelector:
    matchLabels:
      app: frontend
  egress:
  # Allow frontend to call backend API
  - toEndpoints:
    - matchLabels:
        app: backend-api
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: "GET"
          path: "/api/.*"
          headers:
          - "Authorization: Bearer.*"  # Require Authorization header
```

#### 4. Cilium Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-cilium-ingress
  annotations:
    ingress.cilium.io/force-https: "true"
spec:
  ingressClassName: cilium
  tls:
  - hosts:
    - myapp.example.com
    secretName: frontend-tls
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 4180
```

### Benefits of Cilium + OAuth2 Proxy

- L7 network policies enforce security at multiple layers
- mTLS between services (if configured)
- No additional service mesh needed (Cilium provides mesh features)
- eBPF-based performance advantages
- OAuth2 Proxy handles authentication flow

## Option 3: Envoy + External Auth (Advanced)

Use Cilium's Envoy integration with OAuth2 Proxy as external auth service.

### CiliumEnvoyConfig

```yaml
apiVersion: cilium.io/v2
kind: CiliumEnvoyConfig
metadata:
  name: frontend-ext-auth
spec:
  services:
  - name: frontend
    namespace: default
  resources:
  - "@type": type.googleapis.com/envoy.config.listener.v3.Listener
    name: frontend-listener
    filterChains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typedConfig:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          httpFilters:
          # External authorization filter
          - name: envoy.filters.http.ext_authz
            typedConfig:
              "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthz
              httpService:
                serverUri:
                  uri: http://oauth2-proxy.default.svc.cluster.local:4180
                  cluster: oauth2-proxy
                  timeout: 1s
                authorizationRequest:
                  allowedHeaders:
                    patterns:
                    - exact: "cookie"
                    - exact: "authorization"
                authorizationResponse:
                  allowedUpstreamHeaders:
                    patterns:
                    - exact: "x-auth-request-user"
                    - exact: "x-auth-request-email"
                    - exact: "authorization"
          # Router filter
          - name: envoy.filters.http.router
            typedConfig:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
```

### Benefits

- OAuth2 Proxy as auth decision service
- Envoy handles request routing
- Centralized authentication logic
- Can share OAuth2 Proxy across multiple services

## Option 4: Service Mesh (Istio/Linkerd)

Full service mesh with authentication capabilities.

### Istio Example

#### 1. RequestAuthentication

```yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: frontend-jwt-auth
  namespace: default
spec:
  selector:
    matchLabels:
      app: frontend
  jwtRules:
  - issuer: "https://login.microsoftonline.com/{tenant}/v2.0"
    jwksUri: "https://login.microsoftonline.com/{tenant}/discovery/v2.0/keys"
    audiences:
    - "api://your-client-id"
```

#### 2. AuthorizationPolicy

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: frontend-require-jwt
  namespace: default
spec:
  selector:
    matchLabels:
      app: frontend
  action: ALLOW
  rules:
  - from:
    - source:
        requestPrincipals: ["*"]
```

#### 3. OAuth2 Proxy Integration

```yaml
# Still use OAuth2 Proxy for login flow
# Istio validates JWT on subsequent requests
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: frontend-vs
spec:
  hosts:
  - myapp.example.com
  gateways:
  - frontend-gateway
  http:
  - match:
    - uri:
        prefix: "/oauth2/"
    route:
    - destination:
        host: oauth2-proxy
        port:
          number: 4180
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: frontend
        port:
          number: 80
```

### Linkerd Example

Linkerd doesn't have built-in JWT validation, so OAuth2 Proxy is still needed:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  annotations:
    linkerd.io/inject: enabled  # Enable sidecar injection
spec:
  template:
    spec:
      containers:
      - name: oauth2-proxy
        # ... OAuth2 Proxy config
      - name: nginx
        # ... Frontend config
```

## Option 5: Application Gateway + APIM

Enforce authentication at the gateway layer.

### Architecture

```text
User Request
    ↓
Application Gateway (WAF, TLS termination)
    ↓
OAuth2 Proxy (as separate service)
    ↓ (authenticated)
Frontend (nginx)
    ↓ (API calls)
Application Gateway
    ↓
APIM (JWT validation, rate limiting)
    ↓
Backend API
```

### APIM JWT Validation Policy

```xml
<inbound>
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401">
        <openid-config url="https://login.microsoftonline.com/{tenant}/.well-known/openid-configuration" />
        <audiences>
            <audience>api://your-api-id</audience>
        </audiences>
        <required-claims>
            <claim name="scope" match="any">
                <value>user_impersonation</value>
            </claim>
        </required-claims>
    </validate-jwt>
</inbound>
```

### Application Gateway Backend Settings

```bash
# Configure Application Gateway to route to OAuth2 Proxy
az network application-gateway rule create \
  --gateway-name myAppGateway \
  --resource-group rg-myapp \
  --name frontend-rule \
  --rule-type Basic \
  --http-listener frontend-listener \
  --address-pool frontend-pool \
  --http-settings frontend-settings
```

## Option 6: Client-Side SPA Authentication (No Forced Login)

Standard SPA pattern - users see UI before authenticating.

### Architecture

```text
User Request
    ↓
Ingress
    ↓
Frontend (nginx) - serves static files immediately
    ↓ (React loads)
User clicks "Login"
    ↓
OIDC flow in browser (oidc-client-ts)
    ↓
API calls with JWT
    ↓
APIM validates JWT
    ↓
Backend API
```

### When to Use

- Simple applications
- No security requirement for "forced login upfront"
- Want to minimize infrastructure complexity
- Users can view some content before logging in

### Implementation

This is the current Stack 11 implementation in the compose.yml.

## Option 7: Azure Container Apps (Alternative to AKS)

If Easy Auth is critical, consider Container Apps instead of AKS.

### Comparison

| Feature | AKS | Container Apps |
|---------|-----|----------------|
| Easy Auth | Requires OAuth2 Proxy | Built-in |
| Kubernetes | Full control | Partial (Kubernetes API) |
| Complexity | High | Low-Medium |
| Cost | Pay for nodes | Pay per usage |
| Service Mesh | Manual install | Built-in (Envoy) |
| Auto-scaling | Manual config | Built-in |

### Container Apps with Easy Auth

```bash
# Create Container App with Easy Auth
az containerapp create \
  --name frontend \
  --resource-group rg-myapp \
  --environment myenv \
  --image myregistry.azurecr.io/frontend:latest \
  --target-port 80 \
  --ingress external \
  --registry-server myregistry.azurecr.io

# Enable authentication
az containerapp auth update \
  --name frontend \
  --resource-group rg-myapp \
  --enabled true \
  --require-authentication true \
  --unauthenticated-client-action RedirectToLoginPage

# Configure Entra ID
az containerapp auth microsoft update \
  --name frontend \
  --resource-group rg-myapp \
  --client-id "your-client-id" \
  --client-secret-setting-name "aad-secret" \
  --issuer "https://login.microsoftonline.com/your-tenant-id/v2.0"
```

## Recommendation Matrix

### Small to Medium Applications

#### Use: OAuth2 Proxy Sidecar

- Simplest Easy Auth alternative
- Well-documented and maintained
- Works with any ingress controller

### Already Using Cilium

#### Use: Cilium + OAuth2 Proxy

- Leverage existing Cilium investment
- Enhanced L7 security policies
- No additional service mesh needed

### Enterprise with Service Mesh

#### Use: Existing Service Mesh + OAuth2 Proxy

- Integrate auth with existing mesh
- Centralized observability
- mTLS between all services

### Need Easy Auth Features

#### Use: Azure Container Apps

- Simplest solution
- No infrastructure management
- Built-in Easy Auth

### API-First / No Forced Login Required

#### Use: Client-Side SPA + APIM

- Simplest implementation
- Standard SPA pattern
- APIM handles API security

## Security Best Practices

1. **Always use HTTPS**
   - TLS termination at ingress
   - Secure cookies only

2. **Short-lived tokens**
   - Configure appropriate token expiration
   - Enable automatic refresh

3. **Network policies**
   - Restrict pod-to-pod communication
   - Use Cilium or Calico for L7 policies

4. **Secrets management**
   - Use Azure Key Vault for secrets
   - Never commit secrets to Git
   - Rotate secrets regularly

5. **Monitoring**
   - Log authentication events
   - Alert on authentication failures
   - Monitor token usage

## Troubleshooting

### OAuth2 Proxy Issues

#### Problem: Infinite redirect loop

```text
Solution: Check redirect_url matches ingress host
- --redirect-url=https://myapp.example.com/oauth2/callback (correct)
- --redirect-url=http://myapp.example.com/oauth2/callback (wrong if using HTTPS)
```

#### Problem: 403 Forbidden after login

```text
Solution: Check email-domain or allowed groups
- --email-domain=* (allow all)
- --allowed-group=your-group-id (specific groups)
```

#### Problem: Cookies not persisting

```text
Solution: Check cookie-secret and cookie-secure settings
- Generate proper cookie-secret (32 bytes, base64)
- Set cookie-secure=true only with HTTPS
```

### Cilium Policy Issues

#### Problem: Requests blocked by policy

```bash
# Check policy status
kubectl get cnp
kubectl describe cnp frontend-ingress-policy

# View policy logs
cilium policy trace --src-k8s-pod default:frontend-xxx --dst-k8s-pod default:backend-xxx
```

#### Problem: L7 policy not working

```bash
# Verify Envoy is loaded
cilium status | grep Envoy

# Check Envoy logs
kubectl logs -n kube-system cilium-xxx -c cilium-envoy
```

## References

- [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Cilium Network Policies](https://docs.cilium.io/en/stable/security/policy/)
- [Istio Authorization Policy](https://istio.io/latest/docs/reference/config/security/authorization-policy/)
- [Linkerd Authentication](https://linkerd.io/2.14/features/automatic-mtls/)
- [APIM JWT Validation](https://learn.microsoft.com/en-us/azure/api-management/validate-jwt-policy)
