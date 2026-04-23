import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { startServer } from './server.js';

async function listen(server) {
  await new Promise((resolve) => {
    server.listen(0, '127.0.0.1', resolve);
  });

  return server.address();
}

async function close(server) {
  await new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
}

async function withProxyPair(options, run) {
  const backendRequests = [];
  const backend = http.createServer(async (req, res) => {
    const chunks = [];

    for await (const chunk of req) {
      chunks.push(chunk);
    }

    backendRequests.push({
      url: req.url,
      method: req.method,
      headers: req.headers,
      body: Buffer.concat(chunks).toString('utf8'),
    });

    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ ok: true }));
  });

  const backendAddress = await listen(backend);
  const frontend = await startServer({
    port: 0,
    proxyTarget: `http://127.0.0.1:${backendAddress.port}`,
    forwardEasyAuthHeaders: options.forwardEasyAuthHeaders,
    useManagedIdentity: false,
  });

  const frontendAddress = frontend.server.address();
  const baseUrl = `http://127.0.0.1:${frontendAddress.port}`;

  try {
    await run({ baseUrl, backendRequests });
  } finally {
    await close(frontend.server);
    await close(backend);
  }
}

function createFixtureDist() {
  const distDir = fs.mkdtempSync(path.join(os.tmpdir(), 'frontend-react-dist-'));
  fs.mkdirSync(path.join(distDir, 'assets'), { recursive: true });
  fs.writeFileSync(
    path.join(distDir, 'index.html'),
    '<!doctype html><html><head><title>fixture</title></head><body><div id="app"></div></body></html>',
    'utf8',
  );
  fs.writeFileSync(path.join(distDir, 'logged-out.html'), '<html><body>logged out</body></html>', 'utf8');
  fs.writeFileSync(path.join(distDir, 'assets', 'app.js'), 'console.log("fixture");', 'utf8');
  return distDir;
}

test('server proxy preserves the /api path and forwards Easy Auth headers when enabled', async () => {
  await withProxyPair({ forwardEasyAuthHeaders: true }, async ({ baseUrl, backendRequests }) => {
    const response = await fetch(`${baseUrl}/api/v1/ping?source=test`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-zumo-auth': 'easy-auth-token',
        authorization: 'Bearer user-token',
        cookie: 'session=abc123',
        'x-custom-header': 'custom-value',
      },
      body: JSON.stringify({ hello: 'world' }),
    });

    assert.equal(response.status, 200);
    assert.equal(backendRequests.length, 1);
    assert.equal(backendRequests[0].url, '/api/v1/ping?source=test');
    assert.equal(backendRequests[0].headers['x-zumo-auth'], 'easy-auth-token');
    assert.equal(backendRequests[0].headers.authorization, 'Bearer user-token');
    assert.equal(backendRequests[0].headers.cookie, 'session=abc123');
    assert.equal(backendRequests[0].headers['x-custom-header'], 'custom-value');
    assert.equal(backendRequests[0].body, '{"hello":"world"}');
  });
});

test('server proxy can suppress Easy Auth headers while keeping normal request headers', async () => {
  await withProxyPair({ forwardEasyAuthHeaders: false }, async ({ baseUrl, backendRequests }) => {
    const response = await fetch(`${baseUrl}/api/v1/ping`, {
      headers: {
        'x-zumo-auth': 'easy-auth-token',
        authorization: 'Bearer user-token',
        cookie: 'session=abc123',
        'x-custom-header': 'custom-value',
      },
    });

    assert.equal(response.status, 200);
    assert.equal(backendRequests.length, 1);
    assert.equal(backendRequests[0].headers['x-custom-header'], 'custom-value');
    assert.equal(backendRequests[0].headers['x-zumo-auth'], undefined);
    assert.equal(backendRequests[0].headers.authorization, undefined);
    assert.equal(backendRequests[0].headers.cookie, undefined);
  });
});

test('server serves built assets from an injected dist directory', async () => {
  const distDir = createFixtureDist();
  const frontend = await startServer({
    port: 0,
    distDir,
    proxyTarget: '',
    useManagedIdentity: false,
  });

  try {
    const frontendAddress = frontend.server.address();
    const response = await fetch(`http://127.0.0.1:${frontendAddress.port}/assets/app.js`);

    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type') ?? '', /javascript/);
    assert.equal(await response.text(), 'console.log("fixture");');
  } finally {
    await close(frontend.server);
    fs.rmSync(distDir, { recursive: true, force: true });
  }
});

test('server injects runtime config into the SPA shell from an injected dist directory', async () => {
  const distDir = createFixtureDist();
  const frontend = await startServer({
    port: 0,
    distDir,
    proxyTarget: '',
    useManagedIdentity: false,
    env: {
      ...process.env,
      API_BASE_URL: 'https://api.example.test',
      AUTH_METHOD: 'oidc',
    },
  });

  try {
    const frontendAddress = frontend.server.address();
    const response = await fetch(`http://127.0.0.1:${frontendAddress.port}/nested/route`);
    const html = await response.text();

    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type') ?? '', /text\/html/);
    assert.match(html, /window\.RUNTIME_CONFIG/);
    assert.match(html, /https:\/\/api\.example\.test/);
    assert.match(html, /"AUTH_METHOD":"oidc"/);
  } finally {
    await close(frontend.server);
    fs.rmSync(distDir, { recursive: true, force: true });
  }
});
