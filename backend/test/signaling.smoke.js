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

  const callId = 'smoke-' + Date.now();
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

  A.close(); B.close();
  console.log('ALL SIGNALING SMOKE TESTS PASSED');
  process.exit(0);
})().catch(e => { console.error('SMOKE FAILED:', e.message || e); process.exit(1); });
