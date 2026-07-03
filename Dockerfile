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

# ---- assets: cut the regional PMTiles + fetch fonts/sprites ----------------
FROM alpine:3.20 AS assets
ARG PMTILES_VERSION=1.30.3
ARG BBOX=5.5,45.5,17.2,55.1
ARG MAXZOOM=14
RUN apk add --no-cache curl git jq tar ca-certificates
WORKDIR /assets
RUN curl -sSL "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_Linux_x86_64.tar.gz" \
    | tar -xz -C /usr/local/bin pmtiles \
 && pmtiles version
RUN PLANET="https://build.protomaps.com/$(curl -s https://build-metadata.protomaps.dev/builds.json | jq -r 'sort_by(.uploaded)[-1].key')" \
 && echo "planet: $PLANET" \
 && mkdir -p tiles \
 && pmtiles extract "$PLANET" tiles/dach.pmtiles --bbox="$BBOX" --maxzoom="$MAXZOOM"
RUN git clone --depth 1 https://github.com/protomaps/basemaps-assets.git /tmp/a \
 && mkdir -p basemaps \
 && cp -R /tmp/a/fonts basemaps/fonts \
 && cp -R /tmp/a/sprites basemaps/sprites \
 && rm -rf /tmp/a

# ---- runtime ---------------------------------------------------------------
FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    CLIENT_DIST=/app/client/dist \
    ASSETS_DIR=/app/server/assets
COPY --from=deps /app/node_modules ./node_modules
COPY package.json tsconfig.json ./
COPY shared ./shared
COPY server ./server
COPY --from=build /app/client/dist ./client/dist
COPY --from=assets /assets/tiles ./server/assets/tiles
COPY --from=assets /assets/basemaps ./server/assets/basemaps
EXPOSE 3000
USER node
HEALTHCHECK --interval=30s --timeout=4s --start-period=10s \
  CMD wget -qO- http://127.0.0.1:3000/healthz >/dev/null 2>&1 || exit 1
CMD ["npm", "run", "start"]
