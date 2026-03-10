import express from 'express';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { DefaultAzureCredential } from '@azure/identity';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const port = process.env.PORT || 8080;

// Read runtime configuration from environment variables
// Runtime config to inject into frontend (excludes server-only vars like MANAGED_IDENTITY_CLIENT_ID)
const authMethod = process.env.AUTH_METHOD || process.env.AUTH_MODE || '';
const runtimeConfig = {
  API_BASE_URL: process.env.API_BASE_URL || '',
  API_PROXY_ENABLED: process.env.API_PROXY_ENABLED || 'false',
  AUTH_METHOD: authMethod,
  JWT_USERNAME: process.env.JWT_USERNAME || '',
  JWT_PASSWORD: process.env.JWT_PASSWORD || '',
  // Only include AZURE_CLIENT_ID for MSAL mode, not for Easy Auth
  AZURE_CLIENT_ID: authMethod === 'msal' ? (process.env.AZURE_CLIENT_ID || '') : '',
  AZURE_TENANT_ID: process.env.AZURE_TENANT_ID || '',
  AZURE_REDIRECT_URI: process.env.AZURE_REDIRECT_URI || '',
  EASYAUTH_RESOURCE_ID: process.env.EASYAUTH_RESOURCE_ID || '',
};

const proxyTarget = process.env.PROXY_API_URL || '';
const forwardEasyAuthHeaders = process.env.PROXY_FORWARD_EASYAUTH_HEADERS !== 'false';
const useManagedIdentity = process.env.PROXY_MANAGED_IDENTITY_ENABLED === 'true' && proxyTarget;
const easyAuthHeaderWhitelist = [
  'x-zumo-auth',
  'authorization',
  'x-ms-token-aad-access-token',
  'x-ms-token-aad-id-token',
  'x-ms-client-principal',
  'x-ms-client-principal-id',
  'x-ms-client-principal-name',
  'cookie',
];

// Managed Identity credential and token cache
let credential = null;
let tokenCache = { token: null, expiresAt: 0 };

/**
 * Get access token for Function App using Managed Identity
 * Caches token until it expires
 */
async function getManagedIdentityToken() {
  if (!useManagedIdentity) {
    return null;
  }

  // Return cached token if still valid (with 5 min buffer)
  const now = Date.now();
  if (tokenCache.token && tokenCache.expiresAt > now + 300000) {
    return tokenCache.token;
  }

  try {
    // Initialize credential on first use
    if (!credential) {
      credential = new DefaultAzureCredential();
      console.log('Initialized DefaultAzureCredential for Managed Identity');
    }

    // Get token for Function App
    // Scope should be the Function App's application ID URI or client ID
    const functionAppScope = process.env.EASYAUTH_RESOURCE_ID ||
                            process.env.FUNCTION_APP_SCOPE ||
                            `${proxyTarget}/.default`;

    console.log(`Requesting MI token for scope: ${functionAppScope}`);
    const tokenResponse = await credential.getToken(functionAppScope);

    if (!tokenResponse || !tokenResponse.token) {
      console.error('Failed to get Managed Identity token');
      return null;
    }

    // Cache the token
    tokenCache = {
      token: tokenResponse.token,
      expiresAt: tokenResponse.expiresOnTimestamp,
    };

    console.log('Successfully obtained Managed Identity token');
    return tokenResponse.token;
  } catch (error) {
    console.error('Error getting Managed Identity token:', error);
    return null;
  }
}

console.log('Runtime Configuration:', {
  API_BASE_URL: runtimeConfig.API_BASE_URL,
  API_PROXY_ENABLED: runtimeConfig.API_PROXY_ENABLED,
  AUTH_METHOD: runtimeConfig.AUTH_METHOD,
  JWT_USERNAME: runtimeConfig.JWT_USERNAME ? '***' : '(not set)',
  JWT_PASSWORD: runtimeConfig.JWT_PASSWORD ? '***' : '(not set)',
  AZURE_CLIENT_ID: runtimeConfig.AZURE_CLIENT_ID ? '***' : '(not set)',
  AZURE_TENANT_ID: runtimeConfig.AZURE_TENANT_ID || '(not set)',
  AZURE_REDIRECT_URI: runtimeConfig.AZURE_REDIRECT_URI || '(not set)',
  PROXY_API_URL: proxyTarget ? '(configured)' : '(disabled)',
  FORWARD_EASYAUTH_HEADERS: forwardEasyAuthHeaders,
  MANAGED_IDENTITY_PROXY: useManagedIdentity,
});

if (proxyTarget) {
  console.log('Enabling API proxy middleware');
  console.log('Proxy mode:', useManagedIdentity ? 'Managed Identity' : 'Easy Auth headers only');
  console.log('Forward Easy Auth headers:', forwardEasyAuthHeaders);

  // Middleware to add Managed Identity token BEFORE proxy (async supported in Express middleware)
  if (useManagedIdentity) {
    app.use('/api', async (req, res, next) => {
      try {
        const token = await getManagedIdentityToken();
        if (token) {
          req.headers.authorization = `Bearer ${token}`;
          console.log('Added Managed Identity token to request headers');
        } else {
          console.warn('No Managed Identity token available');
        }
      } catch (error) {
        console.error('Error getting MI token:', error);
      }
      next();
    });
  }

  app.use(
    '/api',
    createProxyMiddleware({
      target: proxyTarget,
      changeOrigin: true,
      pathRewrite: { '^/': '/api/' }, // Add /api prefix back after stripping
      logLevel: process.env.NODE_ENV === 'production' ? 'warn' : 'info',
      xfwd: true,
      onProxyReq: (proxyReq, req) => {
        // Easy Auth Headers mode: Forward user's Easy Auth headers
        if (forwardEasyAuthHeaders) {
          easyAuthHeaderWhitelist.forEach((header) => {
            const value = req.headers[header];
            if (value) {
              proxyReq.setHeader(header, value);
            }
          });
        }
      },
    })
  );
}

// Serve static assets (CSS, JS, images) - but NOT index.html
app.use(express.static(path.join(__dirname, 'dist'), { index: false }));

// SPA fallback - inject runtime config into index.html (Express 5 compatible)
app.use((_req, res) => {
  const indexPath = path.join(__dirname, 'dist', 'index.html');
  let html = fs.readFileSync(indexPath, 'utf8');

  // Inject runtime config as inline script BEFORE other scripts
  // Use JSON.stringify to properly escape values and prevent XSS
  const configScript = `
    <script>
      window.RUNTIME_CONFIG = ${JSON.stringify(runtimeConfig)};
    </script>`;

  // Insert before closing </head> tag
  html = html.replace('</head>', `${configScript}</head>`);

  res.send(html);
});

app.listen(port, () => {
  console.log(`Server is running on port ${port}`);
});
