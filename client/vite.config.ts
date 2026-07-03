import { defineConfig } from "vite";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const clientRoot = dirname(fileURLToPath(import.meta.url));

// In dev, proxy the relay + self-hosted assets to the Node server on :3000.
const proxyTarget = "http://localhost:3000";

export default defineConfig({
  root: clientRoot,
  publicDir: resolve(clientRoot, "public"),
  build: {
    outDir: resolve(clientRoot, "dist"),
    emptyOutDir: true,
    target: "es2022",
  },
  server: {
    port: 5173,
    proxy: {
      "/ws": { target: proxyTarget, ws: true },
      "/tiles": { target: proxyTarget },
      "/basemaps": { target: proxyTarget },
      "/healthz": { target: proxyTarget },
    },
  },
});
