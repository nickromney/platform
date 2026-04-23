import fs from 'node:fs';
import fsp from 'node:fs/promises';
import http from 'node:http';
import https from 'node:https';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DEFAULT_DIST_DIR = path.join(__dirname, 'dist');
const MANAGED_IDENTITY_CACHE_WINDOW_MS = 300000;

const CONTENT_TYPES = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.ico', 'image/x-icon'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.map', 'application/json; charset=utf-8'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
]);

const EASYAUTH_HEADER_WHITELIST = [
  'x-zumo-auth',
  'authorization',
  'x-ms-token-aad-access-token',
  'x-ms-token-aad-id-token',
  'x-ms-client-principal',
  'x-ms-client-principal-id',
  'x-ms-client-principal-name',
  'cookie',
];

const HOP_BY_HOP_HEADERS = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
]);

export function createRuntimeConfig(env = process.env) {
  const authMethod = env.AUTH_METHOD || env.AUTH_MODE || '';

  return {
    API_BASE_URL: env.API_BASE_URL || '',
    API_PROXY_ENABLED: env.API_PROXY_ENABLED || 'false',
    AUTH_METHOD: authMethod,
    AUTH_ENABLED: env.AUTH_ENABLED || (authMethod && authMethod !== 'none' ? 'true' : 'false'),
    JWT_USERNAME: env.JWT_USERNAME || '',
    JWT_PASSWORD: env.JWT_PASSWORD || '',
    AZURE_CLIENT_ID: authMethod === 'msal' ? env.AZURE_CLIENT_ID || '' : '',
    AZURE_TENANT_ID: env.AZURE_TENANT_ID || '',
    AZURE_REDIRECT_URI: env.AZURE_REDIRECT_URI || '',
    EASYAUTH_RESOURCE_ID: env.EASYAUTH_RESOURCE_ID || '',
    OIDC_AUTHORITY: env.OIDC_AUTHORITY || '',
    OIDC_CLIENT_ID: env.OIDC_CLIENT_ID || '',
    OIDC_REDIRECT_URI: env.OIDC_REDIRECT_URI || '',
    OIDC_AUTO_LOGIN: env.OIDC_AUTO_LOGIN || 'false',
    OIDC_PROMPT: env.OIDC_PROMPT || '',
    OIDC_FORCE_REAUTH: env.OIDC_FORCE_REAUTH || 'false',
    APIM_SUBSCRIPTION_KEY: env.APIM_SUBSCRIPTION_KEY || '',
  };
}

function buildProxyUrl(proxyTarget, originalUrl) {
  const target = new URL(proxyTarget);
  const targetPath = `${target.pathname.replace(/\/$/, '')}${originalUrl || '/'}`;

  return {
    target,
    path: targetPath || '/',
  };
}

function buildProxyHeaders(req, target, forwardEasyAuthHeaders, useManagedIdentity) {
  const headers = {};

  for (const [header, value] of Object.entries(req.headers)) {
    if (value === undefined) {
      continue;
    }

    const normalized = header.toLowerCase();
    if (HOP_BY_HOP_HEADERS.has(normalized)) {
      continue;
    }

    if (
      !forwardEasyAuthHeaders &&
      EASYAUTH_HEADER_WHITELIST.includes(normalized) &&
      !(useManagedIdentity && normalized === 'authorization')
    ) {
      continue;
    }

    headers[normalized] = value;
  }

  const remoteAddress = req.socket.remoteAddress;
  const forwardedFor = req.headers['x-forwarded-for'];

  headers.host = target.host;
  headers['x-forwarded-for'] =
    forwardedFor && remoteAddress
      ? `${forwardedFor}, ${remoteAddress}`
      : forwardedFor || remoteAddress || '';
  headers['x-forwarded-host'] = req.headers.host || target.host;
  headers['x-forwarded-proto'] =
    req.headers['x-forwarded-proto'] || (req.socket.encrypted ? 'https' : 'http');

  return headers;
}

async function proxyApiRequest(req, res, options) {
  const { proxyTarget, forwardEasyAuthHeaders, useManagedIdentity } = options;
  const { target, path: targetPath } = buildProxyUrl(proxyTarget, req.url);
  const proxyHeaders = buildProxyHeaders(req, target, forwardEasyAuthHeaders, useManagedIdentity);
  const client = target.protocol === 'https:' ? https : http;

  await new Promise((resolve, reject) => {
    const proxyReq = client.request(
      {
        protocol: target.protocol,
        hostname: target.hostname,
        port: target.port || (target.protocol === 'https:' ? 443 : 80),
        method: req.method,
        path: targetPath,
        headers: proxyHeaders,
      },
      async (proxyRes) => {
        try {
          for (const [header, value] of Object.entries(proxyRes.headers)) {
            if (value === undefined || HOP_BY_HOP_HEADERS.has(header.toLowerCase())) {
              continue;
            }

            res.setHeader(header, value);
          }

          res.statusCode = proxyRes.statusCode || 502;
          await pipeline(proxyRes, res);
          resolve();
        } catch (error) {
          reject(error);
        }
      },
    );

    proxyReq.on('error', reject);

    if (req.method === 'GET' || req.method === 'HEAD') {
      proxyReq.end();
      return;
    }

    pipeline(req, proxyReq).catch(reject);
  });
}

function createHttpApp(handler) {
  return {
    listen(port, onListening) {
      const server = http.createServer((req, res) => {
        handler(req, res).catch((error) => {
          console.error('Unhandled server error:', error);
          if (!res.headersSent) {
            res.statusCode = 500;
            res.setHeader('content-type', 'application/json; charset=utf-8');
            res.end(JSON.stringify({ error: 'internal server error' }));
            return;
          }
          res.end();
        });
      });

      return server.listen(port, onListening);
    },
  };
}

function isSafeDistPath(distDir, pathname) {
  const resolvedPath = path.resolve(distDir, `.${pathname}`);
  return resolvedPath.startsWith(path.resolve(distDir));
}

async function serveStaticAsset(distDir, pathname, res) {
  if (!pathname.includes('.') || !isSafeDistPath(distDir, pathname)) {
    return false;
  }

  const assetPath = path.resolve(distDir, `.${pathname}`);
  let stats;
  try {
    stats = await fsp.stat(assetPath);
  } catch {
    return false;
  }

  if (!stats.isFile()) {
    return false;
  }

  const ext = path.extname(assetPath);
  const contentType = CONTENT_TYPES.get(ext);
  if (contentType) {
    res.setHeader('content-type', contentType);
  }
  res.statusCode = 200;
  await pipeline(fs.createReadStream(assetPath), res);
  return true;
}

function injectRuntimeConfig(html, runtimeConfig) {
  const configScript = `
    <script>
      window.RUNTIME_CONFIG = ${JSON.stringify(runtimeConfig)};
    </script>`;

  return html.replace('</head>', `${configScript}</head>`);
}

async function serveSpaShell(distDir, runtimeConfig, res) {
  const indexPath = path.join(distDir, 'index.html');
  const html = await fsp.readFile(indexPath, 'utf8');
  res.statusCode = 200;
  res.setHeader('content-type', 'text/html; charset=utf-8');
  res.end(injectRuntimeConfig(html, runtimeConfig));
}

function stripDefaultScope(resourceOrScope) {
  return resourceOrScope.endsWith('/.default')
    ? resourceOrScope.slice(0, -'/.default'.length)
    : resourceOrScope;
}

function getManagedIdentityRequest(env, resource) {
  if (env.IDENTITY_ENDPOINT && env.IDENTITY_HEADER) {
    const url = new URL(env.IDENTITY_ENDPOINT);
    url.searchParams.set('resource', resource);
    url.searchParams.set('api-version', '2019-08-01');
    return {
      url,
      headers: {
        Metadata: 'true',
        'X-IDENTITY-HEADER': env.IDENTITY_HEADER,
      },
    };
  }

  if (env.MSI_ENDPOINT && env.MSI_SECRET) {
    const url = new URL(env.MSI_ENDPOINT);
    url.searchParams.set('resource', resource);
    url.searchParams.set('api-version', '2017-09-01');
    return {
      url,
      headers: {
        Secret: env.MSI_SECRET,
      },
    };
  }

  const url = new URL('http://169.254.169.254/metadata/identity/oauth2/token');
  url.searchParams.set('api-version', '2018-02-01');
  url.searchParams.set('resource', resource);
  return {
    url,
    headers: {
      Metadata: 'true',
    },
  };
}

function parseManagedIdentityExpiry(tokenResponse) {
  if (typeof tokenResponse.expires_on === 'number') {
    return tokenResponse.expires_on > 1_000_000_000_000
      ? tokenResponse.expires_on
      : tokenResponse.expires_on * 1000;
  }

  if (typeof tokenResponse.expires_on === 'string') {
    const numeric = Number.parseInt(tokenResponse.expires_on, 10);
    if (Number.isFinite(numeric)) {
      return numeric > 1_000_000_000_000 ? numeric : numeric * 1000;
    }
  }

  if (typeof tokenResponse.expires_in === 'number') {
    return Date.now() + tokenResponse.expires_in * 1000;
  }

  if (typeof tokenResponse.expires_in === 'string') {
    const numeric = Number.parseInt(tokenResponse.expires_in, 10);
    if (Number.isFinite(numeric)) {
      return Date.now() + numeric * 1000;
    }
  }

  return Date.now() + 3600 * 1000;
}

export function createApp(options = {}) {
  const env = options.env ?? process.env;
  const port = options.port ?? env.PORT ?? 8080;
  const distDir = options.distDir ?? DEFAULT_DIST_DIR;
  const runtimeConfig = createRuntimeConfig(env);
  const proxyTarget = options.proxyTarget ?? env.PROXY_API_URL ?? '';
  const forwardEasyAuthHeaders =
    options.forwardEasyAuthHeaders ?? env.PROXY_FORWARD_EASYAUTH_HEADERS !== 'false';
  const useManagedIdentity =
    options.useManagedIdentity ?? (env.PROXY_MANAGED_IDENTITY_ENABLED === 'true' && proxyTarget);

  let tokenCache = { token: null, expiresAt: 0 };

  async function getManagedIdentityToken() {
    if (!useManagedIdentity) {
      return null;
    }

    const now = Date.now();
    if (tokenCache.token && tokenCache.expiresAt > now + 300000) {
      return tokenCache.token;
    }

    try {
      const functionAppScope =
        env.EASYAUTH_RESOURCE_ID || env.FUNCTION_APP_SCOPE || `${proxyTarget}/.default`;
      const resource = stripDefaultScope(functionAppScope);
      const { url, headers } = getManagedIdentityRequest(env, resource);

      console.log(`Requesting MI token for resource: ${resource}`);
      const response = await fetch(url, {
        headers,
        signal: AbortSignal.timeout(3000),
      });

      if (!response.ok) {
        console.error('Failed to get Managed Identity token:', response.status);
        return null;
      }

      const tokenResponse = await response.json();
      if (!tokenResponse || typeof tokenResponse.access_token !== 'string') {
        console.error('Failed to get Managed Identity token');
        return null;
      }

      tokenCache = {
        token: tokenResponse.access_token,
        expiresAt: parseManagedIdentityExpiry(tokenResponse),
      };

      console.log('Successfully obtained Managed Identity token');
      return tokenResponse.access_token;
    } catch (error) {
      console.error('Error getting Managed Identity token:', error);
      return null;
    }
  }

  console.log('Runtime Configuration:', {
    API_BASE_URL: runtimeConfig.API_BASE_URL,
    API_PROXY_ENABLED: runtimeConfig.API_PROXY_ENABLED,
    AUTH_METHOD: runtimeConfig.AUTH_METHOD,
    AUTH_ENABLED: runtimeConfig.AUTH_ENABLED,
    JWT_USERNAME: runtimeConfig.JWT_USERNAME ? '***' : '(not set)',
    JWT_PASSWORD: runtimeConfig.JWT_PASSWORD ? '***' : '(not set)',
    AZURE_CLIENT_ID: runtimeConfig.AZURE_CLIENT_ID ? '***' : '(not set)',
    AZURE_TENANT_ID: runtimeConfig.AZURE_TENANT_ID || '(not set)',
    AZURE_REDIRECT_URI: runtimeConfig.AZURE_REDIRECT_URI || '(not set)',
    OIDC_AUTHORITY: runtimeConfig.OIDC_AUTHORITY || '(not set)',
    OIDC_CLIENT_ID: runtimeConfig.OIDC_CLIENT_ID || '(not set)',
    OIDC_REDIRECT_URI: runtimeConfig.OIDC_REDIRECT_URI || '(not set)',
    OIDC_AUTO_LOGIN: runtimeConfig.OIDC_AUTO_LOGIN,
    OIDC_PROMPT: runtimeConfig.OIDC_PROMPT || '(not set)',
    OIDC_FORCE_REAUTH: runtimeConfig.OIDC_FORCE_REAUTH,
    APIM_SUBSCRIPTION_KEY: runtimeConfig.APIM_SUBSCRIPTION_KEY ? '***' : '(not set)',
    PROXY_API_URL: proxyTarget ? '(configured)' : '(disabled)',
    FORWARD_EASYAUTH_HEADERS: forwardEasyAuthHeaders,
    MANAGED_IDENTITY_PROXY: Boolean(useManagedIdentity),
  });

  if (proxyTarget) {
    console.log('Enabling API proxy handler');
    console.log('Proxy mode:', useManagedIdentity ? 'Managed Identity' : 'Easy Auth headers only');
    console.log('Forward Easy Auth headers:', forwardEasyAuthHeaders);
  }

  const app = createHttpApp(async (req, res) => {
    const requestUrl = new URL(req.url || '/', 'http://localhost');
    const pathname = requestUrl.pathname;

    if (proxyTarget && pathname.startsWith('/api')) {
      try {
        if (useManagedIdentity) {
          const token = await getManagedIdentityToken();
          if (token) {
            req.headers.authorization = `Bearer ${token}`;
            console.log('Added Managed Identity token to request headers');
          } else {
            console.warn('No Managed Identity token available');
          }
        }

        await proxyApiRequest(req, res, {
          proxyTarget,
          forwardEasyAuthHeaders,
          useManagedIdentity: Boolean(useManagedIdentity),
        });
        return;
      } catch (error) {
        console.error('Error proxying API request:', error);
        if (!res.headersSent) {
          res.statusCode = 502;
          res.setHeader('content-type', 'application/json; charset=utf-8');
          res.end(JSON.stringify({ error: 'proxy request failed' }));
        }
        return;
      }
    }

    if (await serveStaticAsset(distDir, pathname, res)) {
      return;
    }

    await serveSpaShell(distDir, runtimeConfig, res);
  });

  return {
    app,
    distDir,
    port,
    runtimeConfig,
  };
}

export async function startServer(options = {}) {
  const runtime = createApp(options);

  return await new Promise((resolve) => {
    const server = runtime.app.listen(runtime.port, () => {
      console.log(`Server is running on port ${runtime.port}`);
      resolve({ ...runtime, server });
    });
  });
}

const isEntrypoint = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isEntrypoint) {
  await startServer();
}
