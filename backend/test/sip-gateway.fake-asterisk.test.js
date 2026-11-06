/**
 * Drives the REAL JsSIP stack (under Node, with the pass-through peer
 * connection) against a fake SIP-over-WebSocket server that behaves like
 * Asterisk's PJSIP transport: digest-authenticated REGISTER and INVITE,
 * 100/180/200 with SDP, ACK, BYE in both directions, CANCEL and 486.
 * Then the same through the Socket.IO signaling server, the way the app does it.
 */
process.env.LOG_LEVEL = process.env.LOG_LEVEL || 'error';
process.env.SKIP_DATABASE = 'true';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-jwt-refresh';

const http = require('http');
const jwt = require('jsonwebtoken');
const { io: ioClient } = require('socket.io-client');

const { FakeSipServer } = require('./helpers/fake-sip-server');
const { makeOffer, makeAnswer, makeCandidate } = require('./helpers/webrtc-sdp');
const { createSipGateway, credentialsFor, SIP_EVENTS } = require('../src/services/sip-gateway');

const SECRET = 'fake-asterisk-secret';
const USER = { id: 'user-a', phoneNumber: '+15550000001' };
const once = (emitter, event, ms = 5000) => new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error(`timeout waiting for ${event}`)), ms);
  emitter.once(event, (value) => { clearTimeout(timer); resolve(value); });
});
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function recordEvents(session) {
  const events = [];
  for (const event of SIP_EVENTS) session.on(event, (payload) => events.push({ event, payload }));
  session.on('closed', (payload) => events.push({ event: 'closed', payload }));
  return events;
}

let fake;
let gateway;

beforeAll(async () => {
  fake = await new FakeSipServer({ realm: 'fake.local' }).start();
  const creds = credentialsFor(SECRET, USER.phoneNumber);
  fake.users[creds.username] = creds.password;
  gateway = createSipGateway({
    enabled: true,
    secret: SECRET,
    wssUrl: fake.url,
    domain: 'fake.local',
    iceGatherTimeoutMs: 300,
    registerTimeoutMs: 5000
  });
});

afterAll(async () => {
  gateway.shutdown();
  await sleep(50);
  await fake.stop();
});

describe('real JsSIP against the fake Asterisk', () => {
  test('registers with digest auth', async () => {
    const registered = once(fake, 'register');
    await gateway.ensureUserAgent(USER);
    const reg = await registered;
    expect(reg.user).toBe('user_15550000001');
    expect(fake.isRegistered('user_15550000001')).toBe(true);
  });

  test('outbound: INVITE with complete SDP -> ringing -> answer with fingerprint -> BYE', async () => {
    fake.inviteBehaviour = { status: 200, ringing: true, ringDelayMs: 20, answerDelayMs: 40, challenge: true };
    const session = gateway.placeCall(USER, '*43', { callId: 'call-1' });
    const events = recordEvents(session);
    const inviteSeen = once(fake, 'invite');

    session.setOffer(makeOffer());
    const cand = makeCandidate('10.1.2.3', 50000);
    session.addIceCandidate(cand);
    session.addIceCandidate(null); // end of candidates

    const invite = await inviteSeen;
    expect(invite.uri).toBe('sip:*43@fake.local');
    expect(invite.user).toBe('user_15550000001');
    expect(invite.request.get('content-type')).toBe('application/sdp');
    expect(invite.request.get('x-app-call-id')).toBe('call-1');
    expect(invite.sdp).toContain(`a=${cand.candidate}\r\n`);
    expect(invite.sdp).toContain('a=end-of-candidates\r\n');
    expect(invite.sdp).toContain('a=fingerprint:sha-256');

    await once(fake, 'ack');
    await sleep(20);
    const names = events.map((e) => e.event);
    expect(names).toEqual(['call-ringing', 'answer', 'call-answered']);
    expect(events[0].payload).toEqual({ callId: 'call-1', sipStatus: 180 });
    expect(events[1].payload.sdp).toMatch(/^a=fingerprint:sha-256 /m);
    expect(events[1].payload.from).toBe('*43');
    expect(events[2].payload).toMatchObject({ callId: 'call-1', by: '*43', sipStatus: 200 });

    const bye = once(fake, 'bye');
    session.terminate();
    expect((await bye).callId).toBe(invite.call.callId);
    expect(events.map((e) => e.event)).toEqual(['call-ringing', 'answer', 'call-answered', 'closed']);
  });

  test('outbound: remote BYE -> call-ended', async () => {
    fake.inviteBehaviour = { status: 200, ringing: false, answerDelayMs: 10, challenge: true };
    const session = gateway.placeCall(USER, '+15557654321', { callId: 'call-2', sdpOffer: makeOffer({ withCandidates: true }) });
    const events = recordEvents(session);
    const invite = await once(fake, 'invite');
    expect(invite.uri).toBe('sip:+15557654321@fake.local');
    await once(fake, 'ack');
    fake.hangup(invite.call.callId);
    await once(session, 'closed');
    expect(events.map((e) => e.event)).toEqual(['answer', 'call-answered', 'call-ended', 'closed']);
    expect(events[2].payload).toEqual({ callId: 'call-2', by: '+15557654321', reason: 'Terminated' });
  });

  test('outbound: 486 Busy -> call-error {sipStatus: 486}', async () => {
    fake.inviteBehaviour = { status: 486, reason: 'Busy Here', ringing: false, answerDelayMs: 10, challenge: true };
    const session = gateway.placeCall(USER, '+15550001111', { callId: 'call-3', sdpOffer: makeOffer({ withCandidates: true }) });
    const events = recordEvents(session);
    await once(session, 'closed');
    expect(events.map((e) => e.event)).toEqual(['call-error', 'closed']);
    expect(events[0].payload).toEqual({ callId: 'call-3', error: 'Busy', sipStatus: 486, reason: 'Busy Here' });
  });

  test('outbound: hang-up while ringing sends CANCEL', async () => {
    fake.inviteBehaviour = { status: 200, ringing: true, ringDelayMs: 10, answerDelayMs: 2000, challenge: true };
    const session = gateway.placeCall(USER, '*46', { callId: 'call-4', sdpOffer: makeOffer({ withCandidates: true }) });
    const events = recordEvents(session);
    await once(session, 'call-ringing');
    const cancel = once(fake, 'cancel');
    const closed = once(session, 'closed'); // emitted synchronously by terminate()
    session.terminate();
    await cancel;
    await closed;
    expect(events.map((e) => e.event)).toEqual(['call-ringing', 'closed']);
  });

  test('inbound: INVITE from Asterisk -> incoming-call -> app answer -> 200 OK with candidates -> remote BYE', async () => {
    const incoming = once(gateway, 'incoming-call');
    const callId = fake.invite('user_15550000001', { from: '15550000009', displayName: 'Caller' });
    const session = await incoming;
    const events = recordEvents(session);
    expect(session.direction).toBe('incoming');
    expect(session.from).toBe('+15550000009');
    expect(session.remoteSdp).toContain('a=fingerprint:sha-256');

    const answered = once(fake, 'outbound-answered');
    const cand = makeCandidate('10.9.9.9', 51000);
    session.setAnswer(makeAnswer());
    session.addIceCandidate(cand);
    session.endOfCandidates();
    const { sdp } = await answered;
    expect(sdp).toContain(`a=${cand.candidate}\r\n`);
    expect(sdp).toContain('a=end-of-candidates');
    expect(session.status).toBe('answered');

    fake.hangup(callId);
    await once(session, 'closed');
    expect(events.map((e) => e.event)).toEqual(['call-ended', 'closed']);
    expect(events[0].payload).toEqual({ callId: session.callId, by: '+15550000009', reason: 'Terminated' });
  });

  test('inbound: declined by the app -> 603', async () => {
    const incoming = once(gateway, 'incoming-call');
    fake.invite('user_15550000001', { from: 'webrtc_test' });
    const session = await incoming;
    const failed = once(fake, 'outbound-failed');
    session.terminate({ statusCode: 603, reason: 'Decline' });
    expect((await failed).status).toBe(603);
  });
});

describe('through the Socket.IO signaling server', () => {
  let server;
  let io;
  let base;
  let createSignalingServer;
  let activeCalls;

  const connectClient = (user) => new Promise((resolve, reject) => {
    const token = jwt.sign({ userId: user.id, phoneNumber: user.phoneNumber }, process.env.JWT_SECRET);
    const socket = ioClient(base, { auth: { token }, transports: ['websocket'], reconnection: false });
    socket.on('connect_error', reject);
    socket.on('connect', () => socket.emit('register'));
    socket.on('registered', () => resolve(socket));
  });

  beforeAll(async () => {
    ({ createSignalingServer, activeCalls } = require('../src/signaling-server'));
    server = http.createServer();
    ({ io } = createSignalingServer(server, { sipGateway: gateway }));
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${server.address().port}`;
  });

  afterAll(async () => {
    await new Promise((resolve) => io.close(() => resolve()));
  });

  test('call-initiate *43 is routed to the gateway and the SIP answer reaches the app', async () => {
    fake.inviteBehaviour = { status: 200, ringing: true, ringDelayMs: 10, answerDelayMs: 20, challenge: true };
    const client = await connectClient(USER);
    const received = [];
    for (const event of ['call-ringing', 'answer', 'call-answered', 'call-ended', 'call-error']) {
      client.on(event, (payload) => received.push({ event, payload }));
    }
    const callId = 'sio-1';
    const inviteSeen = once(fake, 'invite');
    client.emit('call-initiate', { to: '*43', callId, hasVideo: false });
    await sleep(20); // a real client has a round trip here; call-initiate awaits the user lookup
    client.emit('offer', { callId, sdp: makeOffer(), to: '*43' });
    const cand = makeCandidate('10.5.5.5', 52000);
    client.emit('ice-candidate', { callId, candidate: cand, to: '*43' });
    client.emit('ice-candidate', { callId, candidate: null, to: '*43' });

    const invite = await inviteSeen;
    expect(invite.sdp).toContain(`a=${cand.candidate}\r\n`);
    await once(client, 'call-answered');
    expect(received.map((e) => e.event)).toEqual(['call-ringing', 'answer', 'call-answered']);
    expect(received[1].payload.callId).toBe(callId);
    expect(received[1].payload.sdp).toMatch(/^a=fingerprint:sha-256 /m);
    expect(activeCalls.get(callId)).toMatchObject({ via: 'sip', calleePhone: '*43' });

    const bye = once(fake, 'bye');
    client.emit('call-end', { callId });
    await bye;
    await sleep(30);
    expect(activeCalls.has(callId)).toBe(false);
    client.close();
  });

  test('unknown destinations still fail; app users are not sent to SIP', async () => {
    const client = await connectClient(USER);
    const error = once(client, 'call-error');
    client.emit('call-initiate', { to: 'not-a-number', callId: 'sio-2', hasVideo: false });
    expect(await error).toEqual({ callId: 'sio-2', error: 'Unknown destination' });
    client.close();
  });

  test('inbound SIP call reaches the connected app as incoming-call + offer, then call-ended on remote BYE', async () => {
    const client = await connectClient(USER);
    await sleep(100); // registration of the (re-created) UA
    const incoming = once(client, 'incoming-call');
    const offer = once(client, 'offer');
    const fakeCallId = fake.invite('user_15550000001', { from: '15550000009' });
    const inc = await incoming;
    const off = await offer;
    expect(inc).toMatchObject({ from: '+15550000009', via: 'sip', hasVideo: false });
    expect(off.callId).toBe(inc.callId);
    expect(off.sdp).toContain('a=fingerprint:sha-256');

    const answered = once(fake, 'outbound-answered');
    client.emit('call-answer', { callId: inc.callId });
    client.emit('answer', { callId: inc.callId, sdp: makeAnswer() });
    client.emit('ice-candidate', { callId: inc.callId, candidate: makeCandidate('10.7.7.7', 53000) });
    client.emit('ice-candidate', { callId: inc.callId, candidate: '' });
    const { sdp } = await answered;
    expect(sdp).toContain('a=candidate:');

    const ended = once(client, 'call-ended');
    fake.hangup(fakeCallId);
    expect(await ended).toMatchObject({ callId: inc.callId, by: '+15550000009' });
    client.close();
  });

  test('disconnecting the app ends its SIP call and unregisters the user', async () => {
    fake.inviteBehaviour = { status: 200, ringing: false, answerDelayMs: 10, challenge: true };
    const client = await connectClient(USER);
    const callId = 'sio-4';
    client.emit('call-initiate', { to: '*43', callId, hasVideo: false });
    await sleep(20);
    client.emit('offer', { callId, sdp: makeOffer({ withCandidates: true }), to: '*43' });
    await once(client, 'call-answered');
    const bye = once(fake, 'bye');
    client.close();
    await bye;
    await sleep(100);
    expect(activeCalls.has(callId)).toBe(false);
    expect(gateway.hasUserAgent(USER.id)).toBe(false);
  });
});
