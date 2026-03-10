# Shared Frontend Package

Shared TypeScript types and utilities for subnet calculator frontends.

## Features

- **Harmonized TypeScript Configuration** - Strict type checking with modern ES2022 features
- **Biome Linting** - Fast, consistent code formatting and linting
- **100% Test Coverage** - Comprehensive test suite with Vitest
- **Type-Safe API Interface** - Shared interface for all API clients

## Usage

### In React Frontend

```typescript
import type { CloudMode, LookupResult } from '@subnet-calculator/shared-frontend'
import { isIpv6, getApiPrefix } from '@subnet-calculator/shared-frontend/api'

const mode: CloudMode = 'Azure'
const address = '2001:db8::/32'

if (isIpv6(address)) {
  const prefix = getApiPrefix(address) // '/api/v1/ipv6'
}
```

### In TypeScript Vite Frontend

```typescript
import type { HealthResponse, ApiResults } from '@subnet-calculator/shared-frontend'
import { handleFetchError, parseJsonResponse } from '@subnet-calculator/shared-frontend/api'

try {
  const response = await fetch('/api/v1/health')
  const health = await parseJsonResponse<HealthResponse>(response)
} catch (error) {
  handleFetchError(error)
}
```

## Development

```bash
# Install dependencies
npm install

# Build
npm run build

# Lint
npm run lint

# Test with coverage
npm run test:coverage
```

## Type Definitions

### CloudMode

Supported cloud provider modes: `Standard` | `AWS` | `Azure` | `OCI`

### Key Interfaces

- `HealthResponse` - API health check response
- `ValidateResponse` - IP address/network validation
- `PrivateCheckResponse` - RFC1918/RFC6598 private address check
- `CloudflareCheckResponse` - Cloudflare IP range check
- `SubnetInfoResponse` - Subnet calculation results
- `LookupResult` - Complete lookup with timing data

## Testing

Tests are written with Vitest and achieve 100% coverage of runtime code.

```bash
npm test
npm run test:coverage
```

## Linting

Biome is configured for fast, consistent linting:

```bash
npm run lint        # Check and fix issues
npm run lint:check  # Check only (CI mode)
```

## Build Output

The package is built as ES modules with TypeScript declaration files:

```text
dist/
├── index.js
├── index.d.ts
├── api/
│   ├── index.js
│   └── index.d.ts
└── types/
    ├── index.js
    └── index.d.ts
```
