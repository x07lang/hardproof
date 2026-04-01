import http from 'node:http';

const bindHost = process.env.MCP_FIXTURE_BIND_HOST || '127.0.0.1';
const port = Number.parseInt(process.env.MCP_FIXTURE_PORT || '18082', 10);
const mcpPath = process.env.MCP_FIXTURE_MCP_PATH || '/mcp';

const server = http.createServer((req, res) => {
  if (req.url !== mcpPath) {
    res.writeHead(404).end();
    return;
  }
  if (req.method !== 'POST') {
    res.writeHead(405).end();
    return;
  }
  res.writeHead(200, { 'content-type': 'text/plain' });
  res.end('this is not json-rpc');
});

server.listen(port, bindHost, () => {
  console.log(`Broken fixture listening at http://${bindHost}:${port}${mcpPath}`);
});

process.on('SIGINT', () => {
  server.close(() => process.exit(0));
});

