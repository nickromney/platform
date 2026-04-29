import http from 'node:http';

const port = Number.parseInt(process.env.PORT || '${{ values.backendPort }}', 10);
const serviceName = process.env.OTEL_SERVICE_NAME || '${{ values.name }}-backend';
const startedAt = Date.now();
const counters = {
  requests: 0,
  durationSeconds: 0,
};

function log(level, message, fields = {}) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    severity: level,
    message,
    'service.name': serviceName,
    ...fields,
  }));
}

function renderMetrics() {
  return [
    '# HELP http_requests_total HTTP requests by method, route, and status.',
    '# TYPE http_requests_total counter',
    `http_requests_total{app="${{ values.name }}",service="${serviceName}"} ${counters.requests}`,
    '# HELP http_request_duration_seconds_sum Total HTTP request duration in seconds.',
    '# TYPE http_request_duration_seconds_sum counter',
    `http_request_duration_seconds_sum{app="${{ values.name }}",service="${serviceName}"} ${counters.durationSeconds.toFixed(6)}`,
    '# HELP process_uptime_seconds Process uptime in seconds.',
    '# TYPE process_uptime_seconds gauge',
    `process_uptime_seconds{app="${{ values.name }}",service="${serviceName}"} ${((Date.now() - startedAt) / 1000).toFixed(3)}`,
    '',
  ].join('\n');
}

const server = http.createServer((request, response) => {
  const started = process.hrtime.bigint();
  response.on('finish', () => {
    const durationSeconds = Number(process.hrtime.bigint() - started) / 1_000_000_000;
    counters.requests += 1;
    counters.durationSeconds += durationSeconds;
    log('INFO', 'request completed', {
      method: request.method,
      path: request.url,
      status: response.statusCode,
      duration_ms: Math.round(durationSeconds * 1000),
    });
  });

  if (request.url === '/metrics') {
    response.writeHead(200, { 'content-type': 'text/plain; version=0.0.4; charset=utf-8' });
    response.end(renderMetrics());
    return;
  }

  if (request.url === '/health' || request.url === '/api/health') {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({
      ok: true,
      service: '${{ values.name }}',
      owner: '${{ values.owner }}',
    }));
    return;
  }

  response.writeHead(404, { 'content-type': 'application/json' });
  response.end(JSON.stringify({ error: 'not_found' }));
});

server.listen(port, '0.0.0.0', () => {
  log('INFO', '${{ values.name }} backend listening', { port });
});
