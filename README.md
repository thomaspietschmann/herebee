# HereBee 🐝

Ephemeral, end-to-end-encrypted live location sharing. Open the app, share the
link, and everyone who opens it sees each other move on a map as a little fantasy
bee face — in real time, nothing stored.

## Honest privacy statement

This is **data-minimised, non-persisted, end-to-end-encrypted** location sharing
for the peer payloads. It is deliberately private, but it is **not "anonymous"** —
that word would be a lie.

- **The server never sees your location, your name, or the key.** A 256-bit secret
  lives in the URL fragment (`#…`), which browsers never send to the server. From it
  the client derives (via HKDF) a routing `roomId` and an AES-256-GCM key. Every update
  is encrypted in the browser; the relay only forwards opaque ciphertext.
- **Web E2EE caveat.** This assumes the delivered client code is trustworthy. A
  malicious or compromised server could ship different JavaScript to future page
  loads; that is the normal hard limit of browser-based end-to-end encryption.
- **No database; room state is RAM-only.** Rooms exist only while someone is connected
  and vanish when the last person leaves. The app stores no coordinates, names, or
  room history.
- **The link is the key.** Anyone with the full link can see the room for its lifetime.
  Share it deliberately; the app cannot revoke a leaked link short of ending the room.
- **IP addresses are the honest limit.** The relay and the map server see your IP for
  the duration of the connection. The app does not intentionally request-log IPs, but
  your proxy, host, load balancer, or platform may keep infrastructure logs. No
  in-browser app can hide your IP from its own infrastructure without Tor/VPN.
- **Self-hosted maps.** Tiles, fonts and sprites are served from this app — no tile CDN
  can profile which areas you pan across.

## Stack

Node + `ws` relay (no Socket.IO) · Vite + vanilla TypeScript · MapLibre GL JS with a
self-hosted Protomaps **PMTiles** basemap · a hand-rolled composable **bee-face
avatar** generator (SVG building blocks assembled from a seeded PRNG, fully offline).
One process serves the client, the map assets and the WebSocket relay.

## Develop

```bash
npm install
npm run fetch-assets      # one-time: pulls a small map extract + fonts/sprites
# tip: BBOX="13.0,52.3,13.8,52.7" MAXZOOM=14 npm run fetch-assets  # just Berlin, fast
npm run dev               # client on :5173 (proxies /ws, /tiles, /basemaps to :3000)
```

Open the printed URL; you'll be redirected to `/r/#<secret>`. Open the same full URL
(including the `#…`) in a second window to see two peers.

## Build & run (single process)

```bash
npm run build             # -> client/dist (bundle + /style/{lang}.json)
npm run fetch-assets      # -> server/assets/{tiles,basemaps}
npm run start             # serves everything on :3000
```

Checks: `npm run typecheck`, `npm run test:vectors` (cross-client conformance —
see `shared/vectors.json`), and `npx tsx test/e2e-relay.ts` against a running
server. Regenerate derived files with `npm run vectors` and `npm run i18n:arb`.

## Deploy

`docker build -t localizer .` bundles the client, server and the small
fonts/sprites. The large DACH **PMTiles archive is NOT baked into the image** — it
lives on a persistent volume mounted at `/app/server/assets/tiles` and is fetched
exactly once by the entrypoint on first boot (`BBOX` / `MAXZOOM` env, DACH defaults),
so rebuilds and redeploys are fast and never re-download it. To refresh the basemap,
delete `dach.pmtiles` on the volume and redeploy.

Runs as one container on one port behind an HTTPS proxy (Traefik/Coolify forward the
WebSocket upgrade transparently). Give the container a generous health-check start
period — the first boot extracts the tiles before serving.

Production env:

- `ALLOWED_ORIGINS=https://your.domain` — restricts the WebSocket to your origin
  (and, when set, requires a browser `Origin` on the upgrade).
- `TRUSTED_PROXY_HOPS=1` — **set this behind a single reverse proxy.** It makes the
  per-IP connection cap key on the real client IP (the entry your proxy appends)
  instead of a spoofable `X-Forwarded-For` value. Default `0` = trust none, use the
  socket IP (correct for direct/dev; wrong behind a proxy, where all clients would
  otherwise share the proxy IP). Set it to the number of trusted proxy hops.
- Resource ceilings (sensible defaults): `MAX_CONNS` (global sockets, 10000),
  `MAX_ROOMS` (5000), `MAX_CONNS_PER_ROOM` (100).

Native-app support (all optional; unset means the feature is simply off):

- `PUBLIC_ORIGIN=https://your.domain` — absolute origin baked into the generated
  map style at `/style/{lang}.json`. Unset, it is derived from the request, which
  is what dev wants.
- `ALLOWED_ORIGINS=...,app://herebee` — add the app origin to let the native
  clients open the WebSocket. The check is browser CSRF hygiene, not
  authentication, so this is an explicit opt-in rather than a default.
- `APPLE_APP_IDS=TEAMID.app.herebee` and `ANDROID_PACKAGE=app.herebee` +
  `ANDROID_CERT_SHA256=AA:BB:…,CC:DD:…` — populate the deep-link association
  documents under `/.well-known/`. Each document 404s until its env is set.

See [`shared/PROTOCOL.md`](shared/PROTOCOL.md) for the cross-client contract and
[`docs/mobile-plan.md`](docs/mobile-plan.md) for the mobile plan.
