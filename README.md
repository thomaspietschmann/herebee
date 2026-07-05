# localizer

Ephemeral, end-to-end-encrypted live location sharing. Open the app, share the
link, and everyone who opens it sees each other move on a map — in real time,
nothing stored.

## Honest privacy statement

This is **data-minimised, non-persisted, end-to-end-encrypted** location sharing.
It is deliberately private, but it is **not "anonymous"** — that word would be a lie.

- **The server never sees your location, your name, or the key.** A 256-bit secret
  lives in the URL fragment (`#…`), which browsers never send to the server. From it
  the client derives (via HKDF) a routing `roomId` and an AES-256-GCM key. Every update
  is encrypted in the browser; the relay only forwards opaque ciphertext.
- **No database, no logs.** Rooms exist only in RAM while someone is connected and
  vanish when the last person leaves. Coordinates and IPs are never written anywhere.
- **The link is the key.** Anyone with the full link can see the room for its lifetime.
  Share it deliberately; the app cannot revoke a leaked link short of ending the room.
- **IP addresses are the honest limit.** The relay and the map server see your IP for
  the duration of the connection (never stored). No in-browser app can hide that from
  its own infrastructure without Tor/VPN.
- **Self-hosted maps.** Tiles, fonts and sprites are served from this app — no tile CDN
  can profile which areas you pan across.

## Stack

Node + `ws` relay (no Socket.IO) · Vite + vanilla TypeScript · MapLibre GL JS with a
self-hosted Protomaps **PMTiles** basemap · DiceBear `shapes` (CC0) building-block
avatars generated offline. One process serves the client, the map assets and the
WebSocket relay.

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
npm run build             # -> client/dist
npm run fetch-assets      # -> server/assets/{tiles,basemaps}
npm run start             # serves everything on :3000
```

## Deploy

`docker build -t localizer .` bundles the client, server and the small
fonts/sprites. The large DACH **PMTiles archive is NOT baked into the image** — it
lives on a persistent volume mounted at `/app/server/assets/tiles` and is fetched
exactly once by the entrypoint on first boot (`BBOX` / `MAXZOOM` env, DACH defaults),
so rebuilds and redeploys are fast and never re-download it. To refresh the basemap,
delete `dach.pmtiles` on the volume and redeploy.

Runs as one container on one port behind an HTTPS proxy (Traefik/Coolify forward the
WebSocket upgrade transparently). Set `ALLOWED_ORIGINS=https://your.domain` in prod.
Give the container a generous health-check start period — the first boot extracts the
tiles before serving.
