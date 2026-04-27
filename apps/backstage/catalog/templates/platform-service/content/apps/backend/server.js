import http from 'node:http';

const port = Number.parseInt(process.env.PORT || '${{ values.backendPort }}', 10);

const server = http.createServer((request, response) => {
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
  console.log(`${{ values.name }} backend listening on ${port}`);
});

