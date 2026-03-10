# Subnet Calculator API - Container App / App Service Version

Pure FastAPI application (no Azure Functions wrapper) for deployment to Azure Container Apps or Azure App Service.

## Key Differences from Azure Functions Version

| Aspect       | Azure Functions               | Container App                |
| ------------ | ----------------------------- | ---------------------------- |
| Entry point  | `function_app.py`             | `main.py`                    |
| ASGI wrapper | `AsgiMiddleware` (required)   | None (FastAPI runs directly) |
| HTTP Server  | Azure Functions host          | **Uvicorn** (ASGI server)    |
| Routes       | `/api/{function}`             | `/subnets/ipv4`, etc.        |
| Dependencies | `azure-functions` + `fastapi` | `fastapi` + `uvicorn`        |
| Deployment   | `func` CLI                    | Docker image                 |

## Why Uvicorn?

- **Industry standard**: Recommended ASGI server in FastAPI documentation
- **Production-ready**: Fast, reliable, used by millions of applications
- **Direct ASGI support**: No wrapper needed (unlike Azure Functions which requires AsgiMiddleware)

## Quick Start

### Local Development with Docker/Podman Compose

```bash
# Build and run
podman-compose up --build -d

# View logs
podman-compose logs -f

# Stop
podman-compose down
```

API will be available at <http://localhost:8000>

### Local Development with uv

```bash
# Install dependencies
uv sync

# Run with uvicorn
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Testing the API

### Health Endpoints

```bash
curl http://localhost:8000/health
curl http://localhost:8000/health/ready
curl http://localhost:8000/health/live
```

### JWT Authentication

```bash
# Login (username: demo, password: password123)
curl -X POST http://localhost:8000/auth/login \
  -d "username=demo&password=password123"

# Returns: {"access_token": "...", "token_type": "bearer"}
```

### Subnet Calculation

```bash
# Get token
TOKEN=$(curl -s -X POST http://localhost:8000/auth/login \
  -d "username=demo&password=password123" | jq -r .access_token)

# Calculate IPv4 subnet
curl -X POST http://localhost:8000/subnets/ipv4 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"network":"192.168.1.0/24","mode":"Azure"}'
```

### API Documentation

- **Swagger UI**: <http://localhost:8000/docs>
- **ReDoc**: <http://localhost:8000/redoc>
- **OpenAPI JSON**: <http://localhost:8000/openapi.json>

## Deployment

See [NEXT-STEPS-CONTAINER-APP.md](../NEXT-STEPS-CONTAINER-APP.md) for detailed deployment instructions to:

- Azure Container Apps (recommended)
- Azure App Service
- Integration with Azure API Management (APIM)

## Authentication Methods

The API supports multiple authentication methods via `AUTH_METHOD` environment variable:

- `none`: No authentication (development only)
- `api_key`: API key via `X-API-Key` header
- `jwt`: JWT bearer tokens
- `azure_swa`: Azure Static Web Apps EasyAuth
- `apim`: Azure API Management (trust APIM validation)

Default: `jwt` (configured in docker-compose.yml)

## Environment Variables

| Variable                          | Description                                      | Default |
| --------------------------------- | ------------------------------------------------ | ------- |
| `AUTH_METHOD`                     | Authentication method                            | `jwt`   |
| `JWT_SECRET_KEY`                  | JWT signing secret (min 32 chars)                | -       |
| `JWT_ALGORITHM`                   | JWT signing algorithm                            | `HS256` |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` | Token expiration                                 | `30`    |
| `JWT_TEST_USERS`                  | JSON map of test users (Argon2 hashed passwords) | -       |

## Project Structure

```text
api-fastapi-container-app/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI app (no Azure Functions wrapper)
│   ├── config.py            # Environment configuration
│   ├── auth.py              # Password hashing utilities
│   ├── auth_utils.py        # get_current_user dependency
│   ├── routers/
│   │   ├── health.py        # Health check endpoints
│   │   ├── auth.py          # JWT login endpoint
│   │   └── subnets.py       # Subnet calculation endpoints
│   └── models/
│       └── subnet.py        # Pydantic models
├── Dockerfile               # Multi-stage build
├── docker-compose.yml       # Local development
├── pyproject.toml           # uv dependencies
└── uv.lock                  # Locked dependencies
```

## Benefits

1. **Pure FastAPI** - No Azure-specific wrappers, more portable
2. **Standard deployment** - Works on any container platform
3. **Better local development** - Direct Uvicorn without Function host emulation
4. **Industry standard** - Uvicorn is recommended by FastAPI docs
5. **Same authentication code** - Reuse all auth logic from Functions version

## Next Steps

See [NEXT-STEPS-CONTAINER-APP.md](../NEXT-STEPS-CONTAINER-APP.md) for:

- Deployment to Azure Container Apps
- Deployment to Azure App Service
- APIM integration
- OpenAPI specification configuration
- CI/CD pipeline setup
