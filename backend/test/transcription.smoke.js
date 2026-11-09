// End-to-end smoke test for call transcription: consent handshake, server-enforced
// caption relay, stop, and the summary endpoint's authorization.
//
//   BASE=http://localhost:3000 npm run smoke:transcription
//
// Without ANTHROPIC_API_KEY on the server the summary request is expected to
// return 503 (not configured); with a key it must return a summary.
const { io } = require('socket.io-client');
const BASE = process.env.BASE || 'http://localhost:3000';

async function request(method, path, body, token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const r = await fetch(BASE + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, json: await r.json() };
}
async function login(phone) {
  const sent = await request('POST', '/api/auth/send-code', { phoneNumber: phone });
  if (!sent.json.devCode) throw new Error('no devCode: ' + JSON.stringify(sent.json));
  const v = await request('POST', '/api/auth/verify-code', { phoneNumber: phone, code: sent.json.devCode });
  return v.json.token;
}
function connect(token) {
  return new Promise((res, rej) => {
    const s = io(BASE, { auth: { token }, transports: ['websocket'] });
    s.on('connect_error', rej);
    s.on('connect', () => s.emit('register'));
    s.on('registered', () => res(s));
  });
}
const once = (s, ev, ms = 3000) => new Promise((res, rej) => {
  const t = setTimeout(() => rej(new Error(`timeout waiting for ${ev}`)), ms);
  s.once(ev, (d) => { clearTimeout(t); res(d); });
});
const nothing = (s, ev, ms = 400) => new Promise((res, rej) => {
  const handler = (d) => rej(new Error(`unexpected ${ev}: ${JSON.stringify(d)}`));
  s.once(ev, handler);
  setTimeout(() => { s.off(ev, handler); res(); }, ms);
});
function assert(cond, msg) { if (!cond) throw new Error('assertion failed: ' + msg); }

(async () => {
  const [tA, tB, tC] = await Promise.all([login('+15550000011'), login('+15550000012'), login('+15550000013')]);
  const [A, B] = await Promise.all([connect(tA), connect(tB)]);
  console.log('✓ users authenticated and connected');

  const callId = 'tx-smoke-' + Date.now();
  const segment = (id, text, isFinal = true) => ({ callId, segment: { id, text, isFinal, startedAt: Date.now() } });

  // Set up an answered call.
  const incoming = once(B, 'incoming-call');
  A.emit('call-initiate', { to: '+15550000012', callId, hasVideo: false });
  await incoming;

  // Requests before the call is answered are refused.
  const early = once(A, 'transcription-state');
  A.emit('transcription-request', { callId });
  assert((await early).state === 'stopped', 'request before answer is refused');
  console.log('✓ transcription refused before the call is answered');

  const answered = once(A, 'call-answered');
  B.emit('call-answer', { callId });
  await answered;

  // Segments are not relayed without consent.
  const noRelay = nothing(B, 'transcript-segment');
  A.emit('transcript-segment', segment('s0', 'should not arrive'));
  await noRelay;
  console.log('✓ captions not relayed before consent');

  // A asks; both see "requested" with the right byYou.
  const reqA = once(A, 'transcription-state');
  const reqB = once(B, 'transcription-state');
  A.emit('transcription-request', { callId });
  const [ra, rb] = await Promise.all([reqA, reqB]);
  assert(ra.state === 'requested' && ra.byYou === true, 'requester sees requested/byYou');
  assert(rb.state === 'requested' && rb.byYou === false, 'peer sees requested/not byYou');
  console.log('✓ request delivered to both sides');

  // The requester cannot approve its own request.
  const selfApprove = nothing(B, 'transcription-state');
  A.emit('transcription-respond', { callId, accepted: true });
  await selfApprove;
  console.log('✓ requester cannot approve its own request');

  // B accepts.
  const actA = once(A, 'transcription-state');
  const actB = once(B, 'transcription-state');
  B.emit('transcription-respond', { callId, accepted: true });
  const [aa, ab] = await Promise.all([actA, actB]);
  assert(aa.state === 'active' && ab.state === 'active', 'both active');
  console.log('✓ consent recorded; transcription active for both');

  // Segments flow both ways and are sanitized.
  const atB = once(B, 'transcript-segment');
  A.emit('transcript-segment', segment('a1', 'Can you send the quote by Wednesday?'));
  const gotB = await atB;
  assert(gotB.segment.text === 'Can you send the quote by Wednesday?' && gotB.from === '+15550000011', 'A→B segment');
  const atA = once(A, 'transcript-segment');
  B.emit('transcript-segment', segment('b1', 'x'.repeat(5000), false));
  const gotA = await atA;
  assert(gotA.segment.text.length === 2000 && gotA.segment.isFinal === false, 'B→A segment truncated');
  console.log('✓ captions relayed both ways (long text truncated)');

  // Summary authorization.
  const transcript = [
    { speaker: 'me', text: 'Can you send the quote by Wednesday?', startedAt: new Date().toISOString() },
    { speaker: 'peer', text: 'Yes, I will email it Wednesday afternoon.', startedAt: new Date().toISOString() }
  ];
  const outsider = await request('POST', `/api/calls/${callId}/summary`, { transcript }, tC);
  assert(outsider.status === 404, `non-participant gets 404 (got ${outsider.status})`);
  const bad = await request('POST', `/api/calls/${callId}/summary`, { transcript: [] }, tA);
  assert(bad.status === 400, `empty transcript gets 400 (got ${bad.status})`);
  const neverTranscribed = await request('POST', '/api/calls/does-not-exist/summary', { transcript }, tA);
  assert(neverTranscribed.status === 404, 'unknown call gets 404');
  const noAuth = await request('POST', `/api/calls/${callId}/summary`, { transcript });
  assert(noAuth.status === 401, 'missing token gets 401');
  const summary = await request('POST', `/api/calls/${callId}/summary`, { transcript }, tA);
  if (summary.status === 503) {
    console.log(`✓ summary endpoint authorized the participant; not configured: "${summary.json.error}"`);
  } else {
    assert(summary.status === 200 && summary.json.summary && typeof summary.json.summary.summary === 'string', `summary ok (got ${summary.status} ${JSON.stringify(summary.json)})`);
    console.log('✓ summary generated:', JSON.stringify(summary.json.summary));
  }

  // Either side can stop; relay stops with it.
  const stA = once(A, 'transcription-state');
  const stB = once(B, 'transcription-state');
  B.emit('transcription-stop', { callId });
  const [sa, sb] = await Promise.all([stA, stB]);
  assert(sa.state === 'stopped' && sa.byYou === false && sb.byYou === true, 'stopped with byYou');
  const afterStop = nothing(B, 'transcript-segment');
  A.emit('transcript-segment', segment('a2', 'after stop'));
  await afterStop;
  console.log('✓ stop delivered to both; captions no longer relayed');

  // Decline path.
  const req2 = once(B, 'transcription-state');
  A.emit('transcription-request', { callId });
  await req2;
  const decA = once(A, 'transcription-state');
  B.emit('transcription-respond', { callId, accepted: false });
  const dec = await decA;
  assert(dec.state === 'declined' && dec.byYou === false, 'declined reaches requester');
  console.log('✓ decline delivered to the requester');

  const ended = once(B, 'call-ended');
  A.emit('call-end', { callId });
  await ended;

  // The consent record outlives the call so summaries can be requested afterwards.
  const afterEnd = await request('POST', `/api/calls/${callId}/summary`, { transcript }, tB);
  assert(afterEnd.status !== 404, `participant can still summarize after the call (got ${afterEnd.status})`);
  console.log('✓ summary still authorized after the call ended');

  A.close(); B.close();
  console.log('ALL TRANSCRIPTION SMOKE TESTS PASSED');
  process.exit(0);
})().catch((e) => { console.error('SMOKE FAILED:', e.message || e); process.exit(1); });
