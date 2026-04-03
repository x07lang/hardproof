import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { createMcpExpressApp } from '@modelcontextprotocol/sdk/server/express.js';
import { SubscribeRequestSchema, UnsubscribeRequestSchema } from '@modelcontextprotocol/sdk/types.js';

function hostHeaderIsLocalhost(hostHeader) {
  if (!hostHeader || typeof hostHeader !== 'string') return false;

  const raw = hostHeader.trim().toLowerCase();
  if (raw.startsWith('[')) {
    const end = raw.indexOf(']');
    const inside = end === -1 ? raw : raw.slice(1, end);
    return inside === '::1';
  }

  const hostname = raw.split(':', 1)[0];
  return hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '::1';
}

function originHeaderIsLocalhost(originHeader) {
  if (!originHeader || typeof originHeader !== 'string') return false;
  try {
    const url = new URL(originHeader);
    const hostname = (url.hostname || '').toLowerCase();
    return hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '::1';
  } catch {
    return false;
  }
}

function enforceDnsRebindingProtection(req, res, next) {
  const host = req.headers.host;
  const origin = req.headers.origin;

  if (!hostHeaderIsLocalhost(host)) {
    res.status(403).end();
    return;
  }
  if (origin !== undefined && !originHeaderIsLocalhost(origin)) {
    res.status(403).end();
    return;
  }
  next();
}

function requireBearerAuth(req, res, next) {
  const expected = process.env.MCP_FIXTURE_AUTH_BEARER || 'test-token';
  const auth = req.headers.authorization;
  if (auth === `Bearer ${expected}`) {
    next();
    return;
  }
  res.status(401).end();
}

export function getServer() {
  const server = new McpServer({ name: 'hardproof-fixture', version: '1.0.0' }, { capabilities: { logging: {} } });

  server.registerTool(
    'test_tool_with_progress',
    {
      description: 'Conformance fixture tool: emits progress notifications',
      inputSchema: {}
    },
    async (_, extra) => {
      const token = extra?._meta?.progressToken;
      if (token !== undefined) {
        for (let i = 1; i <= 3; i++) {
          await extra.sendNotification({
            method: 'notifications/progress',
            params: {
              progressToken: token,
              progress: i,
              total: 3,
              message: `step ${i}/3`
            }
          });
        }
      }
      return { content: [{ type: 'text', text: 'ok' }] };
    }
  );

  server.server.registerCapabilities({ resources: { subscribe: true } });
  server.server.setRequestHandler(SubscribeRequestSchema, async () => ({}));
  server.server.setRequestHandler(UnsubscribeRequestSchema, async () => ({}));

  return server;
}

export function startFixture({ requireAuth = false } = {}) {
  const bindHost = process.env.MCP_FIXTURE_BIND_HOST || '127.0.0.1';
  const port = Number.parseInt(process.env.MCP_FIXTURE_PORT || '18080', 10);
  const mcpPath = process.env.MCP_FIXTURE_MCP_PATH || '/mcp';

  const app = createMcpExpressApp();
  app.use(enforceDnsRebindingProtection);
  if (requireAuth) app.use(requireBearerAuth);

  app.post(mcpPath, async (req, res) => {
    const server = getServer();
    try {
      const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
      await server.connect(transport);
      await transport.handleRequest(req, res, req.body);
      res.on('close', () => {
        transport.close();
        server.close();
      });
    } catch (error) {
      console.error('Error handling MCP request:', error);
      if (!res.headersSent) {
        res.status(500).json({
          jsonrpc: '2.0',
          error: { code: -32603, message: 'Internal server error' },
          id: null
        });
      }
    }
  });

  app.get(mcpPath, async (_req, res) => {
    res.writeHead(405).end(
      JSON.stringify({
        jsonrpc: '2.0',
        error: { code: -32000, message: 'Method not allowed.' },
        id: null
      })
    );
  });

  const server = app.listen(port, bindHost, error => {
    if (error) {
      console.error('Failed to start fixture:', error);
      process.exit(1);
    }
    console.log(`Fixture listening at http://${bindHost}:${port}${mcpPath}`);
  });

  process.on('SIGINT', () => {
    server.close(() => process.exit(0));
  });
}
