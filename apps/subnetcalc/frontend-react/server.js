import express from 'express';
import fs from 'fs';
import http from 'http';
import https from 'https';
import path from 'path';
import { pipeline } from 'node:stream/promises';
import { DefaultAzureCredential } from '@azure/identity';
import { fileURLToPath, pathToFileURL } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

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
  headers['x-forwarded-proto'] = req.headers['x-forwarded-proto'] || req.protocol || 'http';

  return headers;
}

async function proxyApiRequest(req, res, options) {
  const { proxyTarget, forwardEasyAuthHeaders, useManagedIdentity } = options;
  const { target, path: targetPath } = buildProxyUrl(proxyTarget, req.originalUrl);
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

          res.status(proxyRes.statusCode || 502);
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

export function createApp(options = {}) {
  const env = options.env ?? process.env;
  const app = express();
  const port = options.port ?? env.PORT ?? 8080;
  const runtimeConfig = createRuntimeConfig(env);
  const proxyTarget = options.proxyTarget ?? env.PROXY_API_URL ?? '';
  const forwardEasyAuthHeaders =
    options.forwardEasyAuthHeaders ?? env.PROXY_FORWARD_EASYAUTH_HEADERS !== 'false';
  const useManagedIdentity =
    options.useManagedIdentity ?? (env.PROXY_MANAGED_IDENTITY_ENABLED === 'true' && proxyTarget);

  let credential = null;
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
      if (!credential) {
        credential = new DefaultAzureCredential();
        console.log('Initialized DefaultAzureCredential for Managed Identity');
      }

      const functionAppScope =
        env.EASYAUTH_RESOURCE_ID || env.FUNCTION_APP_SCOPE || `${proxyTarget}/.default`;

      console.log(`Requesting MI token for scope: ${functionAppScope}`);
      const tokenResponse = await credential.getToken(functionAppScope);

      if (!tokenResponse || !tokenResponse.token) {
        console.error('Failed to get Managed Identity token');
        return null;
      }

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

    if (useManagedIdentity) {
      app.use('/api', async (req, _res, next) => {
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

    app.use('/api', async (req, res) => {
      try {
        await proxyApiRequest(req, res, {
          proxyTarget,
          forwardEasyAuthHeaders,
          useManagedIdentity: Boolean(useManagedIdentity),
        });
      } catch (error) {
        console.error('Error proxying API request:', error);
        if (!res.headersSent) {
          res.status(502).json({ error: 'proxy request failed' });
        }
      }
    });
  }

  app.use(express.static(path.join(__dirname, 'dist'), { index: false }));

  app.use((_req, res) => {
    const indexPath = path.join(__dirname, 'dist', 'index.html');
    let html = fs.readFileSync(indexPath, 'utf8');

    const configScript = `
    <script>
      window.RUNTIME_CONFIG = ${JSON.stringify(runtimeConfig)};
    </script>`;

    html = html.replace('</head>', `${configScript}</head>`);
    res.send(html);
  });

  return {
    app,
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
