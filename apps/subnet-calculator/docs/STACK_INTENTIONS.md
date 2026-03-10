# Stack Testing Intentions

## Overview

This project demonstrates various Azure architecture patterns for hosting a subnet calculator application. The goal is to provide clear, working examples of when to use different Azure services and authentication patterns.

## Frontend Hosting Options

### Azure Web App

#### When to use

- Traditional web applications with server-side rendering
- Need for custom runtime environments
- Applications requiring WebSockets or long-running connections
- When you need more control over the hosting environment

#### Current examples

Flask frontend with server-side rendering

### Azure Container App

#### When to use

- Microservices architectures
- Event-driven applications
- Applications requiring automatic scaling to zero
- When you want container deployment without Kubernetes complexity

#### Current examples

Container App hosting the FastAPI backend

### Azure Kubernetes Service (AKS) Workload

#### When to use

- Complex microservices requiring orchestration
- Need for advanced networking and service mesh
- Multi-region deployments with sophisticated traffic management
- When you need full Kubernetes capabilities

#### Current examples

Planned implementation

### Azure Storage Account Static Website

#### When to use

- Pure static content (HTML, CSS, JS)
- Single-page applications (SPAs)
- Content that does not require server-side rendering
- Cost-effective hosting for high-traffic sites

#### Current examples

Static HTML frontend

### Azure Static Web Apps

#### When to use

- Modern SPAs with API backends
- Need for integrated authentication (GitHub, Entra ID, etc.)
- Global CDN distribution built-in
- Simplified deployment with GitHub Actions
- When you want frontend and backend as a single unit

#### Current examples

TypeScript Vite frontend with Function App backend via SWA CLI

## Backend API Patterns

### Function App - Public with No Authentication

#### Architecture

- Function App is publicly accessible
- No authentication required
- Any client can call the API directly

#### When to use

- Public APIs (weather, geocoding, etc.)
- Internal tools where network-level security suffices
- Development and testing environments

#### Security considerations

- Rate limiting required
- Input validation critical
- Consider API key for basic protection

#### Current examples

Container App API on port 8090

### Function App - Public with JWT Authentication

#### Architecture

- Function App is publicly accessible
- Application-level JWT validation
- Client obtains token via login endpoint
- Client includes token in Authorization header

#### When to use

- Multi-platform APIs (mobile, web, desktop)
- When clients need to authenticate across services
- Microservices requiring service-to-service auth
- When you need fine-grained permission control

#### Security considerations

- Token refresh strategy required
- Secure token storage (HttpOnly cookies, secure storage)
- Token expiration and revocation

#### Current examples

Azure Function API on port 8080 with JWT middleware

### Function App - SWA Linked Backend

#### Architecture

- Function App is linked to SWA via configuration
- SWA proxies `/api/*` requests to Function App
- Function App can be public or private
- SWA handles authentication, injects headers to backend

#### When to use

- SPA and API deployed as single unit
- Want simplified deployment pipeline
- Need integrated authentication (Entra ID, GitHub, etc.)
- Frontend and backend share same domain (CORS simplified)

#### Security considerations

- Backend can trust SWA-injected headers
- Function App should validate SWA headers
- Can restrict Function App networking to SWA IP ranges

#### Current examples

SWA CLI with linked api-fastapi-azure-function

### Function App - SWA Private Endpoint

#### Architecture

- Function App deployed with private endpoint
- Not accessible from public internet
- Only SWA can reach it via Azure backbone network
- SWA connects via VNet integration or private link

#### When to use

- Sensitive APIs (PII, financial data)
- Compliance requirements (HIPAA, PCI-DSS)
- Defense-in-depth security model
- Production workloads requiring network isolation

#### Security considerations

- Strongest network isolation
- Backend is unreachable without going through SWA
- Requires VNet and private endpoint configuration
- Higher complexity and cost

#### Current examples

Planned implementation with Terraform

## Authentication Patterns

### No Authentication

#### Pattern

- No login required
- All endpoints accessible
- Frontend sends requests directly

#### When to use

- Public data and tools
- Internal-only deployments behind VPN
- Development and testing

#### Example implementations

- swa-04 (Container App, no auth) - port 4280

### Entra ID Protects Frontend Only

#### Pattern

- User must login to access frontend
- SWA redirects unauthenticated users to Entra ID
- After auth, SWA sets cookie
- Frontend can access user info via `/.auth/me`
- Backend receives SWA headers (`x-ms-client-principal`)

#### When to use

- Enterprise applications
- Need Azure AD group-based access control
- SSO with other Microsoft services
- Conditional access policies required

#### Example implementations

- swa-06 (planned) - Entra ID at SWA layer - port 4282

### Entra ID Protects Frontend and Backend

#### Pattern

- User authenticates with Entra ID at frontend
- Frontend obtains access token for backend API
- Browser makes direct API calls with token
- Backend validates Entra ID token

#### When to use

- Frontend and backend have different security boundaries
- Backend used by multiple frontends
- Need API-level permission scoping
- Mobile apps or third-party integrations

#### Security considerations

- Token exposed to browser JavaScript
- Backend must validate token signature and claims
- Requires proper CORS configuration
- Token refresh for long sessions

#### Example implementations

- Planned implementation

## Current Implementation Status

### Working Stacks

#### Direct Launches (7000s ports)

- Azure Function API (port 7071) - JWT auth - WORKING
- Container App API (port 7080) - No auth - WORKING
- Flask frontend (port 7000) - Server-side rendering - WORKING
- Vite frontend (port 7010) - SPA - WORKING

#### Compose Stacks (8000s ports)

- compose-01: Flask + Azure Function (JWT) - port 8000 - WORKING
- compose-02: Static HTML + Container App - port 8001 - WORKING
- compose-03: Flask + Container App - port 8002 - WORKING
- compose-04: TypeScript Vite + Container App - port 8003 - WORKING

#### SWA Stacks (4000s ports)

- swa-04: TypeScript Vite + Container App (no auth) - port 4280 - WORKING
- swa-05: TypeScript Vite + Azure Function (JWT) - port 4281 - PARTIAL
- Bruno CLI tests pass (manual token handling)
- Browser fails with "Invalid token" (auto-auth mechanism broken)
- swa-06: TypeScript Vite + Container App (no auth) - port 4282 - WORKING

### Planned Implementations

#### Frontend Hosting

- Azure Web App deployment examples
- Azure Container App frontend deployment
- AKS deployment with Helm charts
- Storage Account static website deployment

#### Backend Patterns

- Function App (public, no auth) - Container App on 8090 - DONE
- Function App (public, JWT auth) - Azure Function on 8080 - DONE
- Function App (SWA linked, properly configured) - PLANNED
- Function App (SWA private endpoint via Terraform) - PLANNED

#### Authentication

- No auth - DONE
- Entra ID at SWA layer (frontend protection) - PLANNED
- Entra ID end-to-end (frontend and backend) - PLANNED

## Testing Strategy

Each stack should demonstrate:

1. Deployment method
1. Networking configuration
1. Authentication flow
1. Security posture
1. When to use (decision criteria)

Tests should validate:

- API connectivity
- Authentication mechanisms
- Security boundaries (what can and cannot be accessed)
- Browser experience (not just API tests)

## Known Issues

### swa-05 Browser Authentication

Current status: Bruno CLI tests pass but browser frontend shows "Invalid token"

Root cause: Frontend built with VITE_AUTH_ENABLED=true attempts to auto-handle JWT through SWA proxy. This flow is broken.

Impact: Cannot validate JWT auth pattern through browser UI, only through manual API tests

Recommended resolution:

1. Investigate frontend JWT auto-handling with SWA proxy
1. Or switch swa-05 to demonstrate SWA-layer JWT validation (not app-level)
1. Or implement proper SWA route rules for JWT enforcement

## Next Steps

See implementation roadmap for planned work on remaining stack patterns.
