import assert from 'node:assert/strict';
import http from 'node:http';
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
