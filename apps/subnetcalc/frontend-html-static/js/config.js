/**
 * API Configuration
 *
 * This static frontend uses nginx reverse proxy to communicate with the API.
 * The nginx configuration (nginx.conf) proxies /api/* requests to the
 * api-fastapi-container-app backend service.
 *
 * Docker Compose Setup:
 *   - Frontend: http://localhost:8001
 *   - Backend: api-fastapi-container-app:8000 (internal Docker network)
 *   - nginx proxies /api/* to backend
 *
 * For standalone deployment (without nginx proxy):
 *   Set window.API_BASE_URL = 'http://your-api-url' in index.html
 *
 * Example:
 *   <script>window.API_BASE_URL = 'https://api.example.com';</script>
 */

const API_CONFIG = {
  // Default: Use nginx reverse proxy (empty string = relative URLs)
  // nginx.conf forwards /api/* to api-fastapi-container-app:8000
  BASE_URL: "",

  // API paths (nginx proxy handles routing)
  PATHS: {
    HEALTH: "/api/v1/health",
    VALIDATE: "/api/v1/ipv4/validate",
    CHECK_PRIVATE: "/api/v1/ipv4/check-private",
    CHECK_CLOUDFLARE: "/api/v1/ipv4/check-cloudflare",
    SUBNET_INFO: "/api/v1/ipv4/subnet-info",
  },
};

// Override BASE_URL from environment variable if available
// (Used when deploying to external API without nginx proxy)
if (typeof window !== "undefined" && window.API_BASE_URL) {
  API_CONFIG.BASE_URL = window.API_BASE_URL;
}
