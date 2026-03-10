# App Gateway mTLS (Strict) + APIM JWT + Function App (Subnet Calculator)

## Goal

Demonstrate a secure inbound path where a client hosted "anywhere" (Azure/AWS/on-prem) reaches the Subnet Calculator API through:

1. **Azure Application Gateway (public)** as the edge entry point.
2. **API Management (internal, VNet)** as the API gateway.
3. **Azure Function App (private endpoint)** as the backend.

Security requirements:

- **mTLS enforced at the edge** (client certificate required).
- **JWT enforced at APIM** (authorization/claims validation).
- **TLS on every hop**.

This doc focuses on **Option A**: Application Gateway **terminates TLS and enforces mTLS Strict mode** (Terraform-only), and APIM enforces JWT.

## Current repo building blocks

- Existing internal APIM + Function private endpoint + JWT enforcement:
  - `terraform/terragrunt/personal-sub/subnet-calc-internal-apim/`
  - APIM policy template uses `<validate-jwt>`:
    - `terraform/terragrunt/personal-sub/subnet-calc-internal-apim/templates/api-policy.xml.tftpl`
- Existing public APIM example:
  - `terraform/terragrunt/personal-sub/subnet-calc-react-webapp-apim/`

## Proposed target architecture

```text
Client (anywhere)
  - presents client certificate (mTLS)
  - sends Authorization: Bearer <JWT>
        |
        | 1) HTTPS + mTLS (Strict)
        v
Azure Application Gateway (WAF_v2/Standard_v2)
  - validates client cert chain
  - terminates TLS
  - forwards HTTP request (incl Authorization header)
        |
        | 2) HTTPS (new TLS session)
        v
Azure API Management (Internal mode)
  - validate-jwt policy (audience, issuer, roles)
        |
        | 3) HTTPS
        v
Azure Function App (Private Endpoint)
```

### What APIM sees

- In this design, **APIM does not receive the client certificate**.
- APIM receives the HTTP request forwarded by AppGW and can validate the **JWT**.

### Who issues the JWT

- The caller typically **obtains** the JWT from an Identity Provider (Entra ID / Keycloak / etc.).
- The caller then sends:
  - the client certificate (TLS layer) to AppGW, and
  - `Authorization: Bearer <JWT>` (HTTP layer), which APIM validates.

## Security story (for review)

### Controls by layer

1. **Edge admission (mTLS)**
   - AppGW listener requires a valid client certificate (Strict mode).
   - Only clients with certs issued by the trusted client CA chain can connect.

2. **API authorization (JWT)**
   - APIM policy validates JWT signature and claims (audience/issuer/roles).
   - Authorization is independent of the network/mTLS layer.

3. **Network isolation / bypass prevention**
   - APIM in **Internal** mode: not reachable from the internet.
   - Function App has **public access disabled** and is reachable only via private endpoint.
   - Result: clients cannot bypass AppGW to reach APIM or the Function directly.

4. **Encryption on every hop**
   - Client↔AppGW: TLS
   - AppGW↔APIM: TLS
   - APIM↔Function: TLS

## Cloudflare integration considerations

This repo already has Cloudflare Terraform/Terragrunt stacks:

- `terraform/terragrunt/cloudflare-publiccloudexperiments/` (DNS + tooling)
- `terraform/terragrunt/cloudflare-publiccloudexperiments/dns-core/` (records for `publiccloudexperiments.net`)
- `terraform/terragrunt/modules/cloudflare-site/`

### Important: Cloudflare proxy vs AppGW client mTLS

- If Cloudflare is **proxied (orange cloud)**, Cloudflare terminates TLS from the client.
  - In that mode, **client mTLS cannot be enforced at AppGW**, because AppGW sees Cloudflare as the TLS client.
- If you need **client mTLS at AppGW**, Cloudflare should be **DNS only** for that hostname.
  - Cloudflare can still manage DNS and act as registrar.

For a demonstration that requires mTLS at AppGW, prefer:

- `api.publiccloudexperiments.net` (DNS only) → AppGW public IP.

### Certificates: Cloudflare-issued vs AppGW vs client mTLS CA

- **Cloudflare-issued edge certificates** (Universal SSL / Advanced Certificates) are used when Cloudflare is **proxied** and **terminates TLS**.
  - If you run mTLS at AppGW, the hostname should be **DNS only**, so Cloudflare edge certs are not part of the request path.
- With **DNS only**, you must configure an **AppGW server certificate** for `api.publiccloudexperiments.net`.
  - Typically this is a **publicly trusted** certificate (stored as PFX in Key Vault and referenced by AppGW).
- The **client mTLS certificates** are a separate concern:
  - You can use an **internal CA** to issue client certs and upload the **trusted client CA chain (PEM)** to Key Vault.
  - AppGW trusts that CA via `trusted_client_certificate` / `ssl_profile`.

## Terraform plan (no deployment)

### Stack approach

Create a new Terragrunt stack (recommended) rather than heavily mutating the existing one:

- New stack directory:
  - `terraform/terragrunt/personal-sub/subnet-calc-internal-apim-appgw-mtls/`
  - (name bikeshed: the intent is "internal APIM + AppGW + mTLS")

This stack can reuse most of `subnet-calc-internal-apim` and add AppGW.

### Resource changes (delta from `subnet-calc-internal-apim`)

1. **Networking**
   - Add `snet-appgw` subnet dedicated to Application Gateway.

2. **Key Vault (recommended)**
   - Store:
     - AppGW listener certificate (PFX) for `api.publiccloudexperiments.net`.
     - Trusted client CA chain (PEM) used for mTLS client validation.
   - AppGW uses a managed identity to read the secret/cert.

3. **Application Gateway v2**
   - SKU: `WAF_v2` (preferred) or `Standard_v2`.
   - Public IP frontend.
   - HTTPS listener bound to the hostname.
   - `ssl_profile` with client authentication configuration for **Strict mTLS**.
   - `trusted_client_certificate` blocks containing trusted client CA chain(s).
   - Backend pool pointing to APIM internal endpoint.
     - Typically APIM internal FQDN on `azure-api.net` resolves via private DNS.
   - Health probe and routing rules.

4. **APIM**
   - Remains Internal VNet integrated.
   - Keep the existing `validate-jwt` policy.

5. **Function App**
   - Remains private endpoint only.

### Outputs to add

- AppGW public IP / FQDN (for DNS target).
- The APIM audience value already exists in the internal APIM stack; keep exposing it.

## Testing plan (conceptual)

### mTLS + JWT end-to-end

- Use a non-browser client (recommended for predictable client cert handling):

```bash
curl --cert client.crt --key client.key \
  -H "Authorization: Bearer $JWT" \
  https://api.publiccloudexperiments.net/api/<path>
```

Notes:

- Browser SPAs can be awkward for mTLS because client cert selection is user/device managed.
- A server-side client (on-prem service, CI job, test harness) is usually a better mTLS demonstration.

## Next decisions

1. Which IdP should issue JWTs for the demo?
   - Entra ID (real) vs Keycloak (simulated).
2. Cloudflare mode for the API hostname:
   - DNS only (required if client mTLS is enforced at AppGW).
3. Certificate sourcing:
   - AppGW **server** cert: publicly trusted vs internally trusted.
   - AppGW **client mTLS** CA: your own internal CA vs corporate CA, and where the CA chain lives (Key Vault recommended).
