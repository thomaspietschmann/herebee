# syntax=docker/dockerfile:1

# ---- deps: install all node deps (used for build + runtime via tsx) --------
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

# ---- build: compile the client bundle --------------------------------------
FROM deps AS build
WORKDIR /app
COPY . .
RUN npm run build

# ---- assets: fetch fonts + sprites (small; the big tiles live on a volume) -
FROM alpine:3.20 AS assets
ARG BASEMAPS_ASSETS_COMMIT=028c18f713baecad011301ff7a69acc39bcc2ae7
RUN apk add --no-cache git ca-certificates
RUN git init -q /tmp/a \
 && git -C /tmp/a remote add origin https://github.com/protomaps/basemaps-assets.git \
 && git -C /tmp/a fetch -q --depth 1 origin "${BASEMAPS_ASSETS_COMMIT}" \
 && git -C /tmp/a checkout -q FETCH_HEAD \
 && mkdir -p /assets/basemaps \
 && cp -R /tmp/a/fonts /assets/basemaps/fonts \
 && cp -R /tmp/a/sprites /assets/basemaps/sprites \
 && rm -rf /tmp/a

# ---- runtime ---------------------------------------------------------------
FROM node:22-alpine AS runtime
ARG PMTILES_VERSION=1.30.3
ARG PMTILES_SHA256=adda9f979b719416d0c0069f57401a21c32078c46870a94f9bbda95d850f199f
WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    CLIENT_DIST=/app/client/dist \
    ASSETS_DIR=/app/server/assets
# pmtiles CLI + tools for the one-time tile extract done by the entrypoint.
RUN apk add --no-cache curl jq su-exec \
 && curl -fsSL -o /tmp/pmtiles.tar.gz "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_Linux_x86_64.tar.gz" \
 && echo "${PMTILES_SHA256}  /tmp/pmtiles.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/pmtiles.tar.gz -C /usr/local/bin pmtiles \
 && rm /tmp/pmtiles.tar.gz \
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
# The tiles volume mounts at /app/server/assets/tiles. The server starts within
# seconds (any tile extract runs in the background), so a short start period is fine.
HEALTHCHECK --interval=15s --timeout=4s --start-period=20s \
  CMD wget -qO- http://127.0.0.1:3000/healthz >/dev/null 2>&1 || exit 1
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
