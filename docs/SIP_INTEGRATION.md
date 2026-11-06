# SIP Integration Design

How to give the WebRTC Dialer real telephony: calling and receiving calls from
ordinary phone numbers (PSTN) and from SIP endpoints (PBX extensions, other SIP
users), while keeping the iOS app a single-stack WebRTC client.

## Where we are today

| Layer | State |
|-------|-------|
| iOS UI (keypad, contacts, recents, call screens) | Done |
| iOS phone-number auth (REST) | Done, works against the backend |
| iOS WebRTC media (`RTCPeerConnection`, audio session) | **Not implemented** — calls are simulated with a 2 s timer in `CallManager` |
| iOS signaling client (Socket.IO) | **Not implemented** |
| iOS CallKit / PushKit | **Not implemented** (documented in `CALLKIT_INTEGRATION.md`, `VOIP_PUSH_NOTIFICATIONS.md`) |
| Backend REST + Socket.IO signaling | Done, single port, smoke-tested (`npm run smoke`) |
| Backend VoIP push (APNs) | Code exists, needs an APNs key |
| TURN | Not deployed (Google STUN only) |

SIP is therefore **step two**. Step one is making app-to-app WebRTC calls real.
Everything below is designed so the SIP work plugs into that same call path
instead of adding a second calling stack.

## Decision: bridge SIP on the server, not in the app

| Option | Verdict |
|--------|---------|
| **A. Native SIP stack in the app** (Linphone SDK, PJSIP, Telnyx/Twilio iOS SDKs) | Rejected. Adds a second media engine next to GoogleWebRTC, a second CallKit/PushKit integration, SIP registration keep-alives that iOS suspends in the background, and NAT traversal handled twice. SIP credentials would also live on the device. |
| **B. Server-side WebRTC ↔ SIP gateway** | **Chosen.** The app keeps one media stack (WebRTC/Opus/DTLS-SRTP) and one signaling protocol (our Socket.IO events). A media gateway terminates WebRTC on one side and speaks SIP/RTP to carriers and PBXs on the other. |
| **C. Fully managed CPaaS** (Twilio Programmable Voice, Telnyx WebRTC, SignalWire) | Viable fallback. Removes the gateway you host, but replaces our signaling with the vendor's SDK/protocol and locks pricing to one carrier. Documented at the end as "Plan B". |

### Gateway choice: Asterisk (chan_pjsip)

Asterisk natively terminates WebRTC (ICE, DTLS-SRTP, Opus, `webrtc=yes` on a
PJSIP endpoint), speaks SIP over WebSocket (RFC 7118) and classic SIP/UDP/TLS
to trunks, transcodes Opus ↔ G.711/G.722, bridges, records and does DTMF
(RFC 4733). It is free, provider-agnostic and runs in a container next to the
Node backend. Alternatives considered: FreeSWITCH (equally capable, heavier
config), Janus SIP plugin (lighter but a less complete PBX feature set),
Kamailio + rtpengine (carrier scale, far more moving parts).

## Target architecture

```
 iPhone (WebRTC app)                 Backend (Node)                      Asterisk                     Carrier / PBX
 ┌──────────────────┐   Socket.IO   ┌──────────────────────┐  SIP/WSS   ┌──────────────────┐  SIP/TLS   ┌────────────────┐
 │ CallManager      │◄────────────► │ signaling-server.js   │◄─────────►│ PJSIP            │◄─────────►│ Twilio Elastic │
 │ WebRTCClient     │  (existing    │  ├─ app↔app routing    │ (per-user │  ├─ WebRTC ep per│  trunk    │ SIP Trunking,  │
 │ CallKit/PushKit  │   events)     │  └─ sip-gateway.js ────┘  UA)      │  │  app user     │           │ Telnyx, VoIP.ms│
 └────────┬─────────┘               │     (SIP user agents)  │           │  ├─ trunk ep     │           │ or your PBX    │
          │ DTLS-SRTP / Opus (ICE, via TURN when needed)     │           │  └─ dialplan     │  RTP/SRTP │                │
          └──────────────────────────────────────────────────────────────►│  (media bridge)  │◄─────────►│                │
                                                                         └──────────────────┘           └────────────────┘
```

Key idea: **the Node server is the SIP user agent on behalf of each app user.**
The app never learns SIP. It keeps emitting `call-initiate`, `offer`, `answer`,
`ice-candidate`, `call-end`; the server decides whether the far end is another
app user (today's peer-to-peer relay) or a SIP destination (new gateway path),
and in the SIP case it translates:

| App event (Socket.IO) | SIP (Node → Asterisk over WSS) |
|-----------------------|--------------------------------|
| `call-initiate {to: "+1555…"}` + `offer {sdp}` | `INVITE sip:+1555…@asterisk` with the app's SDP as body |
| ← `180 Ringing` | `call-ringing` (new event, maps to CallKit "ringing") |
| ← `200 OK {sdp}` | `answer {sdp}` then `call-answered`; Node sends `ACK` |
| `call-end` | `BYE` (or `CANCEL` before answer) |
| ← `BYE` / `4xx/5xx/6xx` | `call-ended` / `call-error {sipStatus}` |
| DTMF digits during a call | Sent in-band by WebRTC (`RTCDTMFSender`), Asterisk relays as RFC 4733. No signaling needed. |
| Inbound `INVITE` from Asterisk for user X | If X is connected: `incoming-call`. Else VoIP push (existing `voip-push.js`), app connects, server replays `incoming-call` + `offer`. Node answers `100 Trying` / `180 Ringing` meanwhile. |

### ICE: use full gathering, not trickle, on the SIP leg

SIP has no good trickle-ICE story that Asterisk supports. The gateway therefore
collects the app's ICE candidates (`ice-candidate` events) until the app signals
end-of-candidates and only then builds the final SDP for the `INVITE` / `200 OK`.
On the iOS side this means: for SIP destinations, wait for
`iceGatheringState == .complete` (or a 1–2 s cap) before sending the offer.
Asterisk's own candidates come back in one SDP, which the gateway forwards as a
single `answer`. A TURN server (coturn, see `ARCHITECTURE.md`) makes gathering
fast and reliable on cellular.

### Registration and presence

Asterisk routes inbound calls to PJSIP endpoints that are registered. Options:

1. **Gateway registers for each user while they are online** (REGISTER over the
   user's SIP-over-WSS session when the Socket.IO socket connects; unregister on
   disconnect). Inbound calls to an offline user then fail at Asterisk.
2. **Gateway keeps registrations alive for all users** (one long-lived UA per
   user). Inbound calls always reach Node, which wakes the app via VoIP push.
   This is the one that gives "phone-like" behaviour and is the recommended
   target. Cost is one SIP registration per user on Asterisk (fine for thousands).
3. **Dialplan hook instead of registration**: Asterisk dialplan calls a Node
   webhook (`curl` via `func_curl` or ARI) on inbound; Node pushes the app, which
   connects; dialplan then dials the WebRTC endpoint. More code, same result.

Start with (1) for the prototype, move to (2) when VoIP push is wired.

### Routing rule in `signaling-server.js`

```
on call-initiate(to):
  user = db.User.findOne(phoneNumber = to)
  if user exists and is an app user          -> existing app↔app relay (WebSocket or VoIP push)
  else if to matches E.164 or "sip:" URI      -> sipGateway.placeCall(fromUser, to, sdpPromise)
  else                                        -> call-error "Unknown destination"
```

Asterisk's dialplan handles the carrier side: outbound numbers go out the trunk
with the user's assigned caller ID; inbound DIDs map to user endpoints.

## Infrastructure additions

### 1. Asterisk container (`backend/docker-compose.yml`, new `asterisk` service)

```yaml
  asterisk:
    image: andrius/asterisk:20-current   # or build from asterisk/asterisk sources
    network_mode: host                    # simplest for RTP port ranges
    volumes:
      - ./asterisk/etc:/etc/asterisk:ro
      - ./asterisk/certs:/etc/asterisk/keys:ro
```

Ports: 8089/TCP (SIP over WSS), 5061/TCP (SIP/TLS to trunk, optional), 10000–20000/UDP (RTP).

### 2. `backend/asterisk/etc/pjsip.conf` (sketch)

```ini
[transport-wss]
type=transport
protocol=wss
bind=0.0.0.0:8089
cert_file=/etc/asterisk/keys/fullchain.pem
priv_key_file=/etc/asterisk/keys/privkey.pem

; --- template for app users (one endpoint per user, provisioned by Node via ARI or a generated file) ---
[app-user](!)
type=endpoint
context=from-app
disallow=all
allow=opus,ulaw
webrtc=yes                 ; sets ICE, DTLS-SRTP, avpf, rtcp-mux, bundle automatically
dtls_auto_generate_cert=yes
rtp_symmetric=yes
force_rport=yes
rewrite_contact=yes

[user_15550000001](app-user)
auth=auth_15550000001
aors=user_15550000001
callerid="+15550000001" <+15550000001>

[auth_15550000001]
type=auth
auth_type=userpass
username=user_15550000001
password=<generated-by-node, stored server-side only>

[user_15550000001]
type=aor
max_contacts=1
remove_existing=yes

; --- carrier trunk (example: Twilio Elastic SIP Trunking; Telnyx/VoIP.ms are the same shape) ---
[trunk]
type=endpoint
context=from-trunk
disallow=all
allow=ulaw,g722
outbound_auth=trunk-auth
aors=trunk
from_domain=yourdomain.pstn.twilio.com
media_encryption=sdes        ; SRTP toward the carrier
transport=transport-tls

[trunk-auth]
type=auth
auth_type=userpass
username=<trunk-user>
password=<trunk-pass>

[trunk]
type=aor
contact=sip:yourdomain.pstn.twilio.com:5061;transport=tls
```

### 3. `extensions.conf` (sketch)

```ini
[from-app]
; App users dial E.164 numbers; strip "+" for carriers that want it, set caller ID from the endpoint
exten => _+X.,1,NoOp(Outbound to ${EXTEN} from ${CALLERID(num)})
 same => n,Dial(PJSIP/${EXTEN}@trunk,60)
 same => n,Hangup()
; App user calling another app user by number still goes app↔app in Node, never here.

[from-trunk]
; Inbound DID -> the app user that owns it (lookup can be static or via func_odbc / curl to Node)
exten => _+1555XXXXXXX,1,NoOp(Inbound ${EXTEN} from ${CALLERID(num)})
 same => n,Set(TARGET=${SHELL(curl -s https://api.example.com/internal/did/${EXTEN})})
 same => n,Dial(PJSIP/${TARGET},45)
 same => n,Voicemail(${TARGET}@default,u)   ; optional
 same => n,Hangup()
```

### 4. Node `sip-gateway.js` (new module under `backend/src/services/`)

* SIP stack: **JsSIP** running under Node with the `ws` WebSocket (lightweight,
  proven against Asterisk) — or **drachtio-srf** + drachtio-server if a
  carrier-grade B2BUA is needed later. JsSIP is enough for one UA per user.
* One `JsSIP.UA` per app user, connecting to `wss://asterisk:8089/ws` with the
  endpoint credentials Node generated when the user first authenticated.
* `placeCall(user, destination, sdpOffer) → RTCSession`; wires session events to
  the Socket.IO events in the table above.
* Inbound `newRTCSession` → `incoming-call` to the app (or VoIP push), holds the
  SIP transaction until the app's `answer` arrives, then `session.answer(sdp)`.
* Because the gateway only passes SDP through, **no media touches Node**; media
  flows app ↔ Asterisk directly (through TURN when necessary).

### 5. Provisioning

When a user verifies their phone number (`/api/auth/verify-code`), also create
their PJSIP endpoint/auth/aor. Two ways: write to Asterisk's realtime database
(Postgres via `res_pjsip` realtime — natural once `SKIP_DATABASE=false`), or
generate `pjsip_users.conf` and `pjsip reload`. Realtime is the production
answer; file generation is fine for the prototype.

### 6. Phone numbers (DIDs) and trunk

* Buy numbers from the trunk provider; map each DID to a user in a new `dids`
  table (or a `sipDid` column on `users`).
* Twilio Elastic SIP Trunking, Telnyx and VoIP.ms all work with the trunk
  config above; costs are roughly $1/month per DID plus ~$0.005–0.01/min.
* Legal/operational: E911 registration for each DID, STIR/SHAKEN attestation is
  handled by the carrier, and outbound caller ID must be a number you own.
* Toll-fraud controls (do this before exposing the trunk): per-user daily minute
  caps, block premium-rate/international prefixes by default, alert on spikes.

## iOS changes (after the WebRTC call layer exists)

Small, because the app never speaks SIP:

1. `CallManager.startCall(to:)` already takes any phone number. Add
   `destinationType` (`.appUser` / `.pstn`) returned by a new
   `GET /api/user/lookup?phone=` so the UI can show "Calling via phone network".
2. For `.pstn` destinations, gather ICE fully before emitting `offer` (see ICE
   section).
3. Handle the new `call-ringing` event (CallKit `reportOutgoingCall(with:startedConnectingAt:)`).
4. DTMF keypad during a call → `RTCDTMFSender.insertDtmf` on the audio sender
   (Asterisk converts to RFC 4733 for the carrier). The keypad UI already exists
   in `ActiveCallView`.
5. Nothing new for inbound: VoIP push → CallKit → `incoming-call` + `offer`,
   exactly as app-to-app.

## Phased delivery

| Phase | Scope | Done when |
|-------|-------|-----------|
| 0 | **Real WebRTC app↔app calls** — `WebRTCClient`, `SignalingClient` (Socket.IO over the existing events), CallKit, audio session, basic PushKit | Two iPhones on the deployed backend hold a two-way audio call |
| 1 | Asterisk in docker-compose with the WSS transport, one test user endpoint, TLS certs; coturn | A browser softphone (JsSIP demo page) registers to Asterisk and calls an echo test extension |
| 2 | `sip-gateway.js` with per-user UAs, routing rule in signaling, outbound to Asterisk echo/playback extension | iPhone dials `*43`-style echo test through the gateway; audio both ways; hang-up both directions |
| 3 | Carrier trunk + one DID, outbound PSTN, caller ID, fraud caps | iPhone calls a real phone number |
| 4 | Inbound PSTN → DID → user → VoIP push → CallKit | A real phone calls the DID and the locked iPhone rings natively |
| 5 | Hardening: realtime PJSIP provisioning in Postgres, call records for Recents, SRTP on trunk, monitoring (`pjsip show registrations`, Asterisk AMI/ARI metrics) | Production checklist in `SECURITY.md` satisfied |

Rough effort: Phase 0 is the largest (it is the core of the app). Phases 1–2
are mostly configuration and a ~400-line Node module. Phases 3–4 are mostly
provider setup plus push wiring that `voip-push.js` already anticipates.

## Plan B: managed CPaaS instead of Asterisk

If hosting Asterisk is unwanted, Telnyx WebRTC or Twilio Programmable Voice give
the same user-facing result. Trade-offs: their iOS SDKs replace our
`SignalingClient` + `WebRTCClient` for PSTN calls (so app↔app and app↔PSTN
would use different code paths unless *all* calls go through the vendor), the
per-minute price is 2–5× a bare SIP trunk, and inbound still needs VoIP push
through their APIs. Choose this if time-to-first-PSTN-call matters more than
cost and independence.

## Open questions to settle before Phase 1

* Carrier: Twilio (easiest console, SRTP/TLS trunks), Telnyx (cheaper, good
  API), VoIP.ms (cheapest, UDP-only trunks), or an existing PBX to connect to?
* Do users get their own DID each, or does the app share one business number
  with extension-style routing?
* Hosting for Asterisk: same VM/Fly machine as the backend (RTP needs UDP port
  ranges — Fly supports UDP on dedicated IPs; Render does not), or a small VPS.
