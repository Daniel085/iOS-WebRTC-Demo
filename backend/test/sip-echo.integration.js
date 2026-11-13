#!/usr/bin/env node
/**
 * Integration check for Phase 2: dial Asterisk's echo test through the backend.
 *
 *   BASE=http://localhost:3000 PHONE=+15550000003 npm run sip:integration
 *
 * Needs a running backend with SIP_ENABLED=true that can reach Asterisk
 * (backend/asterisk/README.md). The script signs in over REST, connects to the
 * signaling server, emits call-initiate -> offer -> ice-candidate (+ end of
 * candidates) exactly like the app, and asserts that Asterisk's SDP answer
 * (with a=fingerprint) and call-answered come back, then hangs up.
 *
 * The offer is synthetic (no media stack in Node), so audio does not flow;
 * Asterisk will drop the call after its DTLS timeout. The script hangs up
 * long before that.
 */
const { io } = require('socket.io-client');
const { makeOffer, makeCandidate } = require('./helpers/webrtc-sdp');

const BASE = process.env.BASE || 'http://localhost:3000';
const PHONE = process.env.PHONE || '+15550000003';
const DEST = process.env.DEST || '*43';
const TIMEOUT_MS = parseInt(process.env.TIMEOUT_MS || '20000', 10);

const log = (...args) => console.log(new Date().toISOString().slice(11, 23), ...args);

async function post(path, body) {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`${path} -> ${r.status} ${JSON.stringify(j)}`);
  return j;
}

function waitFor(socket, event, ms = TIMEOUT_MS) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timed out after ${ms} ms waiting for '${event}'`)), ms);
    const onError = (err) => { clearTimeout(timer); socket.off(event, onEvent); reject(new Error(`call-error: ${JSON.stringify(err)}`)); };
    const onEvent = (payload) => { clearTimeout(timer); socket.off('call-error', onError); resolve(payload); };
    socket.once(event, onEvent);
    if (event !== 'call-error') socket.once('call-error', onError);
  });
}

(async () => {
  const health = await fetch(`${BASE}/health`).then((r) => r.json()).catch((e) => { throw new Error(`backend not reachable at ${BASE}: ${e.message}`); });
  log(`backend ${BASE} healthy (${health.environment})`);

  const sent = await post('/api/auth/send-code', { phoneNumber: PHONE });
  if (!sent.devCode) throw new Error('send-code returned no devCode: use SMS_PROVIDER=mock on the backend');
  const { token } = await post('/api/auth/verify-code', { phoneNumber: PHONE, code: sent.devCode });
  log(`signed in as ${PHONE} (verify-code also provisions the PJSIP endpoint when SIP_ENABLED=true)`);

  const socket = io(BASE, { auth: { token }, transports: ['websocket'], reconnection: false });
  await new Promise((resolve, reject) => {
    socket.on('connect_error', reject);
    socket.on('connect', () => socket.emit('register'));
    socket.on('registered', resolve);
  });
  log('socket connected and registered');
  socket.on('call-ringing', (p) => log('← call-ringing', JSON.stringify(p)));
  socket.on('call-ended', (p) => log('← call-ended', JSON.stringify(p)));

  const callId = require('crypto').randomUUID(); // call IDs must be UUIDs
  const answer = waitFor(socket, 'answer');
  const answered = waitFor(socket, 'call-answered');

  socket.emit('call-initiate', { to: DEST, callId, hasVideo: false });
  log(`→ call-initiate ${DEST} (${callId})`);
  await new Promise((resolve) => setTimeout(resolve, 100)); // let the server register the call first
  socket.emit('offer', { callId, sdp: makeOffer(), to: DEST });
  const cand = makeCandidate();
  socket.emit('ice-candidate', { callId, candidate: cand, to: DEST });
  socket.emit('ice-candidate', { callId, candidate: null, to: DEST }); // end of candidates -> INVITE goes out
  log(`→ offer + 1 host candidate (${cand.candidate.split(' ')[4]}) + end-of-candidates`);

  let sdp;
  try {
    ({ sdp } = await answer);
  } catch (error) {
    const m = /call-error: (.*)/.exec(error.message);
    if (m) {
      const err = JSON.parse(m[1]);
      let hint = '';
      if (err.error === 'User not found') hint = ' (backend has SIP_ENABLED!=true)';
      else if (err.error === 'SIP gateway unavailable') hint = ' (backend cannot register with Asterisk: check ASTERISK_WSS_URL, SIP_GATEWAY_SECRET, that the endpoint exists: `pjsip show endpoints`)';
      else if (err.sipStatus === 503) hint = ' (Congestion(): E.164 numbers need the Phase 3 trunk; dial *43 instead)';
      else if (err.sipStatus === 404) hint = ' (no such extension in extensions.conf [from-app])';
      else if (err.sipStatus === 488) hint = ' (Asterisk rejected the SDP: check webrtc=yes and codecs on the app-user template)';
      throw new Error(`call failed: ${JSON.stringify(err)}${hint}`);
    }
    throw error;
  }
  log('← answer', `${sdp.length} bytes`);
  if (!/^a=fingerprint:/m.test(sdp)) throw new Error(`answer SDP has no a=fingerprint (DTLS-SRTP not negotiated):\n${sdp}`);
  const fp = /^a=fingerprint:(.*)$/m.exec(sdp)[1];
  log(`✓ answer SDP carries a DTLS fingerprint: ${fp.slice(0, 40)}…`);
  const ice = /^a=candidate:/m.test(sdp) ? 'with' : 'WITHOUT';
  log(`  answer SDP ${ice} ICE candidates; c= ${(/^c=(.*)$/m.exec(sdp) || [])[1]}`);

  const ans = await answered;
  log('✓ call-answered', JSON.stringify(ans));

  await new Promise((resolve) => setTimeout(resolve, 1000));
  socket.emit('call-end', { callId });
  log('→ call-end');
  await new Promise((resolve) => setTimeout(resolve, 500));
  socket.close();
  console.log(`\nSIP ECHO INTEGRATION PASSED (${PHONE} -> ${DEST} via ${BASE})`);
  process.exit(0);
})().catch((error) => {
  console.error('\nSIP ECHO INTEGRATION FAILED:', error.message || error);
  process.exit(1);
});
