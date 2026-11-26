# Asterisk for the WebRTC Dialer (Phases 1–2)

Asterisk is the WebRTC ↔ SIP media gateway described in
[`docs/SIP_INTEGRATION.md`](../../docs/SIP_INTEGRATION.md). The Node backend
is the SIP user agent for every app user (`src/services/sip-gateway.js`); the
iPhone never speaks SIP. This directory holds everything the `asterisk`
service in [`docker-compose.yml`](../docker-compose.yml) needs.

```
asterisk/
├── etc/                 mounted at /etc/asterisk (read-only)
│   ├── pjsip.conf       WS/WSS transports, app-user template, webrtc_test endpoint, #tryinclude pjsip_users.conf
│   ├── pjsip_users.conf GENERATED per app user by the backend (gitignored)
│   ├── extensions.conf  *43 echo, *44 playback, *45 tone, *46 ringing, endpoint-to-endpoint, E.164 → 503 until Phase 3
│   ├── rtp.conf         RTP 10000–10100/udp, ICE + STUN
│   ├── http.conf        WebSocket on 8088 (ws) and 8089 (wss, TLS)
│   ├── manager.conf     AMI user "gateway" for `pjsip reload`
│   ├── modules.conf     res_pjsip, res_http_websocket, codec_opus, …
│   ├── asterisk.conf / logger.conf
└── certs/               mounted at /etc/asterisk/keys (read-only)
    └── make-certs.sh    self-signed fullchain.pem + privkey.pem (gitignored)
```

Image: `andrius/asterisk:22` (Asterisk 22 LTS on Debian; `andrius/asterisk:22-alpine`
also works). Docker is **not** installed on the development Mac this was written
on, so run the steps below on a machine with Docker (a Linux VPS is the natural
home for Asterisk anyway, because RTP needs a UDP port range).

## 1. Certificates (once)

The WSS transport needs a certificate. For the prototype, self-signed is fine:

```bash
cd backend/asterisk/certs
./make-certs.sh 192.168.4.20      # the IP or host name phones/browsers will use
```

Browsers (and later the iPhone) must trust it once: open
`https://<host>:8089/ws` in the browser and accept the warning. Real
deployments: use Let's Encrypt certificates and point `http.conf`
(`tlscertfile`, `tlsprivatekey`) at them.

The key is written world-readable (`chmod 644`) because the container's
`asterisk` user must read it. That is acceptable for a throw-away prototype
cert only.

## 2. Start

```bash
cd backend
docker compose up asterisk              # add -d to detach
docker compose logs -f asterisk
```

Ports published by the compose file:

| Port | Purpose |
|------|---------|
| 8088/tcp | SIP over plain WebSocket (`ws://host:8088/ws`) — the Node gateway when it runs next to Asterisk; do not expose publicly |
| 8089/tcp | SIP over secure WebSocket (`wss://host:8089/ws`) — browsers and phones |
| 5038/tcp (127.0.0.1 only) | AMI, used by the backend for `pjsip reload` |
| 10000–10100/udp | RTP (`rtp.conf`) |

On Linux you can replace the port list with `network_mode: host` (no NAT for RTP).

## 3. Verify

```bash
docker compose exec asterisk asterisk -rx "core show version"
docker compose exec asterisk asterisk -rx "pjsip show transports"      # transport-ws, transport-wss
docker compose exec asterisk asterisk -rx "http show status"           # HTTP/WS 8088, HTTPS/WSS 8089 enabled
docker compose exec asterisk asterisk -rx "pjsip show endpoints"       # webrtc_test + user_… from pjsip_users.conf
docker compose exec asterisk asterisk -rx "pjsip show contacts"        # who is registered right now (Contact per AOR)
docker compose exec asterisk asterisk -rx "pjsip show registrations"   # OUTBOUND registrations only (trunk, Phase 3) — empty for now
docker compose exec asterisk asterisk -rx "module show like opus"      # codec_opus present? (see modules.conf comment)
docker compose exec asterisk asterisk -rx "dialplan show from-app"
```

`pjsip show endpoints` lists every endpoint with its AOR and contact state
(`Unavail` until something registers). `pjsip show contacts` is the quickest
way to see that the gateway (or a browser) is registered. `pjsip show
registrations` is Asterisk's view of registrations *it* sends out, so it stays
empty until a carrier trunk exists.

Live SIP trace while testing: `asterisk -rx "pjsip set logger on"` and watch
`docker compose logs -f asterisk`.

### 3a. Browser softphone (Phase 1 acceptance test)

Any JsSIP-based softphone works; the JsSIP demo at <https://tryit.jssip.net/>
is the quickest:

| Field | Value |
|-------|-------|
| SIP URI | `sip:webrtc_test@<host>` (host = what you used in `make-certs.sh`) |
| SIP password | `webrtc_test_pass` |
| WebSocket URI | `wss://<host>:8089/ws` |
| Via transport / Registrar | leave default; **Session Timers: off** |
| Use preloaded Route | off |

Accept the certificate at `https://<host>:8089/ws` first, then Login. The
status should turn to *registered* and `pjsip show contacts` lists
`webrtc_test/sip:…;transport=ws`. Dial `*43`: after the prompt, you hear
yourself back (echo test). `*44` plays a file, `*45` a continuous tone, `*46`
rings for 8 s before answering.

If the browser connects but registration fails with 401/403, the password or
the domain in the SIP URI does not match `pjsip.conf`. If the call connects
but there is no audio, see "NAT and Docker" below.

### 3b. Node gateway + integration script (Phase 2 acceptance test)

In `backend/.env`:

```ini
SIP_ENABLED=true
ASTERISK_WSS_URL=ws://127.0.0.1:8088/ws     # backend on the Docker host; use wss://host:8089/ws + ASTERISK_TLS_INSECURE=true otherwise
ASTERISK_DOMAIN=127.0.0.1                   # must match the host part the endpoint identifies with
SIP_GATEWAY_SECRET=pick-a-long-random-string
ASTERISK_USERS_CONF=./asterisk/etc/pjsip_users.conf
ASTERISK_AMI_HOST=127.0.0.1
ASTERISK_AMI_SECRET=change-me-gateway-ami   # = manager.conf [gateway] secret
```

Then:

```bash
npm start                                   # backend logs "✓ SIP gateway enabled: …"
npm run sip:integration                     # PHONE=+15550000003 by default
```

The script signs in (which writes the user's endpoint to `pjsip_users.conf`
and reloads PJSIP over AMI), connects to the signaling server, emits
`call-initiate *43` → `offer` → `ice-candidate` → end-of-candidates like the
app, and asserts that `answer` arrives with `a=fingerprint` followed by
`call-answered`, then hangs up. Its offer is synthetic, so there is no audio
in this test; the iPhone is the first client with real media.

When the backend runs inside compose (`docker compose up`), the defaults in
`docker-compose.yml` already point it at `ws://asterisk:8088/ws` and the AMI
on `asterisk:5038`; set `SIP_ENABLED=true` and `SIP_GATEWAY_SECRET` in `.env`.

### 3c. Inbound path

With an app user connected (its UA registered — `pjsip show contacts` shows
`user_1555…`), dial `user_15550000001` from the browser softphone. Asterisk
`Dial()`s the user's endpoint, the gateway turns the INVITE into
`incoming-call` + `offer` for the app, and the app's `answer` becomes the 200 OK.

## 4. How users are provisioned

`POST /api/auth/verify-code` calls `provisionSipUser()`
(`src/services/sip-provisioning.js`):

1. derives the SIP credentials `user_<digits>` / `HMAC(SIP_GATEWAY_SECRET, username)` —
   nothing is stored, so the gateway and the config always agree;
2. upserts a marked block (`;; BEGIN user_… / ;; END user_…`) into
   `pjsip_users.conf`, which `pjsip.conf` pulls in with `#tryinclude`;
3. runs `pjsip reload` through AMI (`ASTERISK_AMI_*`). Without AMI it logs
   `docker compose exec asterisk asterisk -rx "pjsip reload"` for you to run.

The file is shared between the backend and the Asterisk container through the
`./asterisk/etc` bind mount. Rotating `SIP_GATEWAY_SECRET` rewrites each
user's block the next time they sign in.

Production: switch to PJSIP realtime (Postgres via `res_config_pgsql` /
sorcery) once `SKIP_DATABASE=false`; endpoints are then rows, no reload needed,
and the same `credentialsFor()` fills the `ps_auths` password column.

## 5. NAT and Docker

Media is the part that needs care:

* **Docker bridge network** (the default compose setup): Asterisk's ICE host
  candidates carry the container IP. Either map them in `rtp.conf`
  (`[ice_host_candidates]`, `172.18.0.x => <host IP>`), or set
  `external_media_address` / `external_signaling_address` on `transport-wss`
  in `pjsip.conf`, or use `network_mode: host` on Linux.
* **RTP ports**: `rtp.conf` uses 10000–10100 and compose publishes exactly
  that range. Keep them in sync if you widen it.
* **STUN**: `stunaddr=stun.l.google.com:19302` lets Asterisk add a
  server-reflexive candidate when it has internet access.
* **TURN** (coturn) is still the plan for cellular clients; see `ARCHITECTURE.md`.
* **Opus**: `codec_opus` is Sangoma's binary module. Echo passes Opus through
  without it; `Playback()` transcodes, so if `module show like opus` is empty,
  the client must also offer ulaw (the app-user template allows `opus,ulaw`).

## 6. Not verified yet

Written and reviewed against the Asterisk 22 documentation, but **not run**:
Docker is not available on the Mac this was developed on. The gateway itself
is covered by `npm test`, which drives the real JsSIP stack against a fake
SIP-over-WebSocket server (digest auth, INVITE/180/200/ACK/BYE/CANCEL, 486,
inbound INVITE). What still needs a Docker host:

1. `docker compose up asterisk` starts cleanly with this `etc/` (watch for
   module-load errors, especially `codec_opus`).
2. Browser softphone registers and `*43` echoes (3a).
3. `npm run sip:integration` passes against it (3b).
4. iPhone build with real WebRTC dials `*43` and hears itself (needs the
   app-side ICE-gathering change from `docs/SIP_INTEGRATION.md`, "iOS changes").
