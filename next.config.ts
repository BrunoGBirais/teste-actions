import type { NextConfig } from "next";

// Origin of the n8n instance for this environment, without /webhook
// (Preview -> dev n8n, Production -> prod n8n). The browser calls /n8n/* on
// this site and the request is forwarded server-side, so prod n8n can stay on
// plain HTTP without mixed-content errors and webhooks need no CORS.
const n8nOrigin = (process.env.N8N_WEBHOOK_ORIGIN ?? "").replace(/\/+$/, "");

const nextConfig: NextConfig = {
  async rewrites() {
    if (!n8nOrigin) {
      console.warn("N8N_WEBHOOK_ORIGIN is not set: /n8n/* will not reach n8n.");
      return [];
    }
    return [{ source: "/n8n/:path*", destination: `${n8nOrigin}/webhook/:path*` }];
  },
};

export default nextConfig;
