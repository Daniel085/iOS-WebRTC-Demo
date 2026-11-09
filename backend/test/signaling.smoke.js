// End-to-end smoke test: two users authenticate over REST, connect to Socket.IO
// on the SAME port, and complete call-initiate -> incoming-call -> offer -> answer -> call-end.
const { io } = require('socket.io-client');
const BASE = process.env.BASE || 'http://localhost:3000';

async function post(path, body) {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json();
  if (!r.ok) throw new Error(`${path} -> ${r.status} ${JSON.stringify(j)}`);
  return j;
}
async function login(phone) {
  const sent = await post('/api/auth/send-code', { phoneNumber: phone });
  if (!sent.devCode) throw new Error('no devCode in response: ' + JSON.stringify(sent));
  const v = await post('/api/auth/verify-code', { phoneNumber: phone, code: sent.devCode });
  return v.token;
}
function connect(token) {
  return new Promise((res, rej) => {
    const s = io(BASE, { auth: { token }, transports: ['websocket'] });
    s.on('connect_error', rej);
    s.on('connect', () => { s.emit('register'); });
    s.on('registered', () => res(s));
  });
}
const once = (s, ev) => new Promise(r => s.once(ev, r));

(async () => {
  const [tA, tB] = await Promise.all([login('+15550000001'), login('+15550000002')]);
  console.log('✓ both users authenticated (devCode flow)');
  const [A, B] = await Promise.all([connect(tA), connect(tB)]);
  console.log('✓ both sockets connected + registered on', BASE);

  const callId = require('crypto').randomUUID(); // call IDs must be UUIDs
  const incoming = once(B, 'incoming-call');
  A.emit('call-initiate', { to: '+15550000002', callId, hasVideo: false });
  const inc = await incoming;
  console.log('✓ B got incoming-call from', inc.from);

  const offerAtB = once(B, 'offer');
  A.emit('offer', { callId, sdp: 'v=0 fake-offer', to: '+15550000002' });
  console.log('✓ offer forwarded:', (await offerAtB).sdp);

  const answeredAtA = once(A, 'call-answered');
  const answerAtA = once(A, 'answer');
  B.emit('call-answer', { callId });
  B.emit('answer', { callId, sdp: 'v=0 fake-answer' });
  await answeredAtA; console.log('✓ A got call-answered');
  console.log('✓ answer forwarded:', (await answerAtA).sdp);

  const iceAtA = once(A, 'ice-candidate');
  B.emit('ice-candidate', { callId, candidate: 'candidate:1 fake', to: '+15550000001' });
  console.log('✓ ice-candidate forwarded:', (await iceAtA).candidate);

  const endedAtB = once(B, 'call-ended');
  A.emit('call-end', { callId });
  await endedAtB; console.log('✓ B got call-ended');

  // A malformed call ID is refused before the call exists...
  const badIdError = once(A, 'call-error');
  A.emit('call-initiate', { to: '+15550000002', callId: 'not-a-uuid', hasVideo: false });
  const err = await badIdError;
  if (!/Invalid call ID/.test(err.error)) throw new Error('expected "Invalid call ID", got ' + JSON.stringify(err));
  console.log('✓ non-UUID call ID rejected:', err.error);

  // ...and a caller that drops mid-call must end the call without taking the server down.
  const droppedCallId = require('crypto').randomUUID();
  const incoming2 = once(B, 'incoming-call');
  A.emit('call-initiate', { to: '+15550000002', callId: droppedCallId, hasVideo: false });
  await incoming2;
  const endedByDrop = once(B, 'call-ended');
  A.close();
  const ended = await endedByDrop;
  if (ended.reason !== 'disconnection') throw new Error('expected reason "disconnection", got ' + JSON.stringify(ended));
  await new Promise(r => setTimeout(r, 500));
  const health = await fetch(BASE + '/health');
  if (!health.ok) throw new Error('server unhealthy after a caller disconnect: ' + health.status);
  console.log('✓ caller disconnect ended the call and the server is still healthy');

  B.close();
  console.log('ALL SIGNALING SMOKE TESTS PASSED');
  process.exit(0);
})().catch(e => { console.error('SMOKE FAILED:', e.message || e); process.exit(1); });
