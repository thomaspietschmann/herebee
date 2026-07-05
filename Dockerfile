# syntax=docker/dockerfile:1

# ---- deps: install all node deps (used for build + runtime via tsx) --------
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --no-audit --no-fund

# ---- build: compile the client bundle --------------------------------------
FROM deps AS build
WORKDIR /app
COPY . .
RUN npm run build

# ---- assets: fetch fonts + sprites (small; the big tiles live on a volume) -
FROM alpine:3.20 AS assets
RUN apk add --no-cache git ca-certificates
RUN git clone --depth 1 https://github.com/protomaps/basemaps-assets.git /tmp/a \
 && mkdir -p /assets/basemaps \
 && cp -R /tmp/a/fonts /assets/basemaps/fonts \
 && cp -R /tmp/a/sprites /assets/basemaps/sprites \
 && rm -rf /tmp/a

# ---- runtime ---------------------------------------------------------------
FROM node:22-alpine AS runtime
ARG PMTILES_VERSION=1.30.3
WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    CLIENT_DIST=/app/client/dist \
    ASSETS_DIR=/app/server/assets
# pmtiles CLI + tools for the one-time tile extract done by the entrypoint.
RUN apk add --no-cache curl jq su-exec \
 && curl -sSL "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_Linux_x86_64.tar.gz" \
    | tar -xz -C /usr/local/bin pmtiles \
 && pmtiles version
COPY --from=deps /app/node_modules ./node_modules
COPY package.json tsconfig.json ./
COPY shared ./shared
COPY server ./server
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --from=build /app/client/dist ./client/dist
COPY --from=assets /assets/basemaps ./server/assets/basemaps
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && mkdir -p /app/server/assets/tiles \
 && chown -R node:node /app/server/assets
EXPOSE 3000
# The tiles volume mounts at /app/server/assets/tiles.
HEALTHCHECK --interval=30s --timeout=4s --start-period=15m \
  CMD wget -qO- http://127.0.0.1:3000/healthz >/dev/null 2>&1 || exit 1
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
