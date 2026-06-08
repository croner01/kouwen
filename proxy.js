/**
 * KouWen API Gateway — Reverse Proxy
 *
 * Routes incoming cloudflared traffic to the correct k8s backend service:
 *   /api/v1/agent/*   → agent   (port 30082)
 *   /api/v1/execute   → sandbox (port 30081)
 *   /*                → backend (port 30083)
 */
const http = require('http');
const httpProxy = require('http-proxy');

const TARGETS = {
  agent:   { host: 'localhost', port: 30082 },
  sandbox: { host: 'localhost', port: 30081 },
  backend: { host: 'localhost', port: 30083 },
};

function routeTarget(path) {
  if (path === '/api/v1/agent/chat' || path.startsWith('/api/v1/agent/chat?')) return TARGETS.agent;
  if (path === '/api/v1/execute' || path.startsWith('/api/v1/execute/') || path.startsWith('/api/v1/execute?')) return TARGETS.sandbox;
  return TARGETS.backend;
}

const proxy = httpProxy.createProxyServer({
  proxyTimeout: 600_000, // 10 min for long SSE streaming
  timeout: 600_000,
});

// Suppress noisy proxy error logs for aborted / timed-out streams
proxy.on('error', (err, req, res) => {
  if (res && !res.headersSent) {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ detail: 'Bad Gateway' }));
  }
});

const server = http.createServer((req, res) => {
  const target = routeTarget(req.url);
  console.log(`${new Date().toISOString()} ${req.method} ${req.url} → ${target.host}:${target.port}`);

  proxy.web(req, res, { target });
});

const PORT = 30080;
server.listen(PORT, () => {
  console.log(`KouWen API Gateway listening on port ${PORT}`);
  console.log(`  /api/v1/agent/*  → agent   (:${TARGETS.agent.port})`);
  console.log(`  /api/v1/execute  → sandbox (:${TARGETS.sandbox.port})`);
  console.log(`  /*               → backend (:${TARGETS.backend.port})`);
});
