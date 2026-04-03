import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

function parseArgs(argv) {
  const out = { serverEntry: '', expectTool: '' };
  const args = [...argv];
  out.serverEntry = args.shift() || '';
  while (args.length) {
    const flag = args.shift();
    if (flag === '--expect-tool') {
      out.expectTool = args.shift() || '';
      continue;
    }
    throw new Error(`Unknown arg: ${flag}`);
  }
  return out;
}

async function main() {
  const { serverEntry, expectTool } = parseArgs(process.argv.slice(2));
  if (!serverEntry) {
    console.error('Usage: node _shared/stdio_smoke_client.mjs <server-entry.mjs> [--expect-tool <name>]');
    process.exit(2);
  }

  const client = new Client({ name: 'hardproof-stdio-smoke', version: '0.0.0' });
  const transport = new StdioClientTransport({
    command: 'node',
    args: [serverEntry],
    stderr: 'pipe'
  });

  const timeoutMs = 10_000;
  const timeout = setTimeout(() => {
    console.error(`Timed out after ${timeoutMs}ms`);
    process.exit(1);
  }, timeoutMs);

  try {
    await client.connect(transport);
    const tools = await client.listTools();
    if (expectTool) {
      const found = (tools.tools || []).some(t => t?.name === expectTool);
      if (!found) {
        console.error(`Expected tool not found: ${expectTool}`);
        process.exit(1);
      }
    }
    await client.close();
  } finally {
    clearTimeout(timeout);
  }
}

main().catch(error => {
  const message = error?.message || String(error);
  console.error(`stdio smoke client error: ${message}`);
  process.exit(1);
});
