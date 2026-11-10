/**
 * Unit tests for the SIP gateway with a mocked JsSIP UA:
 *   - SDP assembly from the app's offer + trickled ICE candidates
 *   - routing predicate (E.164 / sip: / feature codes)
 *   - SIP event -> Socket.IO event mapping, both directions
 *   - provisioning file generation
 */
process.env.LOG_LEVEL = process.env.LOG_LEVEL || 'error';

const EventEmitter = require('events');
const fs = require('fs');
const os = require('os');
const path = require('path');

const sdpUtils = require('../src/services/sip/sdp');
const { PassthroughPeerConnection } = require('../src/services/sip/passthrough-peer-connection');
const {
  createSipGateway, credentialsFor, sipUsernameFor, SIP_EVENTS
} = require('../src/services/sip-gateway');
const provisioning = require('../src/services/sip-provisioning');
const { makeOffer, makeAnswer, makeCandidate } = require('./helpers/webrtc-sdp');

const SECRET = 'unit-test-secret';
const USER = { id: 'u1', phoneNumber: '+15550000001' };
const flush = () => new Promise((resolve) => setImmediate(resolve));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const once = (emitter, event) => new Promise((resolve) => emitter.once(event, resolve));

// ---- fake JsSIP ----------------------------------------------------------------

class FakeRTCSession extends EventEmitter {
  constructor(ua, target, options, direction = 'outgoing') {
    super();
    this.ua = ua;
    this.target = target;
    this.options = options || {};
    this.direction = direction;
    this.ended = false;
    this.established = false;
    this.connection = new PassthroughPeerConnection({});
    for (const [event, handler] of Object.entries(this.options.eventHandlers || {})) this.on(event, handler);
    if (direction === 'outgoing') {
      // Like JsSIP: the peer connection is created synchronously inside ua.call().
      this.emit('peerconnection', { peerconnection: this.connection });
      this.connection.createOffer()
        .then((d) => this.connection.setLocalDescription(d))
        .then(() => {
          this.sentSdp = this.connection.localDescription.sdp;
          ua.sentInvites.push(this);
          ua.emit('invite', this);
        })
        .catch(() => this.emit('failed', { originator: 'local', cause: 'WebRTC Error', message: null }));
    }
  }

  isEnded() { return this.ended; }
  isEstablished() { return this.established; }

  terminate(options = {}) {
    this.ended = true;
    this.terminatedWith = options;
    if (this.established) this.emit('ended', { originator: 'local', cause: 'Terminated' });
    else this.emit('failed', { originator: 'local', cause: this.direction === 'incoming' ? 'Rejected' : 'Canceled', message: null });
  }

  answer() {
    this.emit('peerconnection', { peerconnection: this.connection });
    return this.connection.createAnswer()
      .then((d) => this.connection.setLocalDescription(d))
      .then(() => {
        this.sentSdp = this.connection.localDescription.sdp;
        this.established = true;
        this.ua.emit('answered', this);
        this.emit('accepted', { originator: 'local' });
      });
  }

  // --- remote side, driven by tests
  remoteRinging(code = 180) { this.emit('progress', { originator: 'remote', response: { status_code: code } }); }
  remoteAnswer(sdp) {
    this.emit('sdp', { originator: 'remote', type: 'answer', sdp });
    this.established = true;
    this.emit('accepted', { originator: 'remote', response: { status_code: 200 } });
  }
  remoteBye() { this.ended = true; this.emit('ended', { originator: 'remote', cause: 'Terminated' }); }
  remoteFail(status, reason, cause) {
    this.ended = true;
    this.emit('failed', { originator: 'remote', cause, message: { status_code: status, reason_phrase: reason } });
  }
}

class FakeUA extends EventEmitter {
  constructor({ failRegistrations = 0, failStatus = 404 } = {}) {
    super();
    this.started = false;
    this.stopped = false;
    this.sentInvites = [];
    this.registerCalls = 0;
    this.failRegistrations = failRegistrations;
    this.failStatus = failStatus;
  }
  start() {
    this.started = true;
    setImmediate(() => { this.emit('connected', {}); this._register(); });
  }
  register() { this.registerCalls++; setImmediate(() => this._register()); }
  _register() {
    if (this.failRegistrations > 0) {
      this.failRegistrations--;
      this.emit('registrationFailed', { response: { status_code: this.failStatus }, cause: 'Not Found' });
    } else {
      this.emit('registered', {});
    }
  }
  stop() { this.stopped = true; }
  isConnected() { return this.started && !this.stopped; }
  call(target, options) { return new FakeRTCSession(this, target, options, 'outgoing'); }
  /** Simulate an inbound INVITE from Asterisk. */
  incoming(fromUser, sdp) {
    const session = new FakeRTCSession(this, null, {}, 'incoming');
    session.remote_identity = { uri: { user: fromUser } };
    this.emit('newRTCSession', { originator: 'remote', session, request: { body: sdp } });
    return session;
  }
}

function makeGateway(overrides = {}, uaOptions = {}) {
  const uas = [];
  const gateway = createSipGateway({
    enabled: true,
    secret: SECRET,
    wssUrl: 'wss://pbx.example:8089/ws',
    iceGatherTimeoutMs: 100,
    registerTimeoutMs: 2000,
    ...overrides
  }, {
    createUserAgent: ({ credentials }) => {
      const ua = new FakeUA(typeof uaOptions === 'function' ? uaOptions(credentials) : uaOptions);
      ua.credentials = credentials;
      uas.push(ua);
      return ua;
    }
  });
  return { gateway, uas };
}

/** Collect every app-facing event a session emits, in order. */
function recordEvents(session) {
  const events = [];
  for (const event of SIP_EVENTS) session.on(event, (payload) => events.push({ event, payload }));
  session.on('closed', (payload) => events.push({ event: 'closed', payload }));
  return events;
}

// ---- SDP helpers ---------------------------------------------------------------

describe('sdp helpers', () => {
  test('isSipDestination accepts E.164, sip URIs and feature codes only', () => {
    expect(sdpUtils.isSipDestination('+15550000001')).toBe(true);
    expect(sdpUtils.isSipDestination('*43')).toBe(true);
    expect(sdpUtils.isSipDestination('sip:echo@pbx.example')).toBe(true);
    expect(sdpUtils.isSipDestination('sips:1000@pbx.example:5061')).toBe(true);
    expect(sdpUtils.isSipDestination('5551212')).toBe(false);
    expect(sdpUtils.isSipDestination('bob')).toBe(false);
    expect(sdpUtils.isSipDestination('')).toBe(false);
    expect(sdpUtils.isSipDestination(null)).toBe(false);
  });

  test('sipTargetFor builds request URIs at the Asterisk domain', () => {
    expect(sdpUtils.sipTargetFor('*43', 'pbx.example')).toBe('sip:*43@pbx.example');
    expect(sdpUtils.sipTargetFor('+15551234567', 'pbx.example')).toBe('sip:+15551234567@pbx.example');
    expect(sdpUtils.sipTargetFor('sip:x@y', 'pbx.example')).toBe('sip:x@y');
  });

  test('normalizeCandidate handles W3C objects, strings and end-of-candidates markers', () => {
    expect(sdpUtils.normalizeCandidate({ candidate: 'candidate:1 1 udp 1 10.0.0.1 5000 typ host', sdpMid: '0', sdpMLineIndex: 0 }))
      .toEqual({ line: 'a=candidate:1 1 udp 1 10.0.0.1 5000 typ host', sdpMid: '0', sdpMLineIndex: 0 });
    expect(sdpUtils.normalizeCandidate('a=candidate:2 1 udp 1 10.0.0.1 5001 typ host').line).toBe('a=candidate:2 1 udp 1 10.0.0.1 5001 typ host');
    expect(sdpUtils.normalizeCandidate('3 1 udp 1 10.0.0.1 5002 typ host').line).toBe('a=candidate:3 1 udp 1 10.0.0.1 5002 typ host');
    expect(sdpUtils.normalizeCandidate({ sdp: 'candidate:4 1 udp 1 10.0.0.1 5003 typ host', sdpMLineIndex: '1' }).sdpMLineIndex).toBe(1);
    for (const eoc of [null, undefined, '', { candidate: '' }, { candidate: null }, { endOfCandidates: true }]) {
      expect(sdpUtils.isEndOfCandidates(eoc)).toBe(true);
    }
  });

  test('assembleSdp folds candidates into the right m-section, dedupes and marks end-of-candidates', () => {
    const base = [
      'v=0', 'o=- 1 1 IN IP4 0.0.0.0', 's=-', 't=0 0', 'a=group:BUNDLE 0 1',
      'm=audio 9 UDP/TLS/RTP/SAVPF 111', 'a=mid:0', 'a=fingerprint:sha-256 AA',
      'm=video 9 UDP/TLS/RTP/SAVPF 96', 'a=mid:1'
    ].join('\n');
    const audio = { candidate: 'candidate:1 1 udp 1 10.0.0.1 5000 typ host', sdpMid: '0', sdpMLineIndex: 0 };
    const video = { candidate: 'candidate:9 1 udp 1 10.0.0.1 6000 typ host', sdpMid: '1' }; // no index -> by mid
    const out = sdpUtils.assembleSdp(base, [audio, audio, video]);
    const lines = out.split('\r\n');
    expect(out.endsWith('\r\n')).toBe(true);
    expect(out).not.toMatch(/[^\r]\n/);
    const audioIdx = lines.indexOf('m=audio 9 UDP/TLS/RTP/SAVPF 111');
    const videoIdx = lines.indexOf('m=video 9 UDP/TLS/RTP/SAVPF 96');
    const a1 = lines.indexOf('a=candidate:1 1 udp 1 10.0.0.1 5000 typ host');
    const v9 = lines.indexOf('a=candidate:9 1 udp 1 10.0.0.1 6000 typ host');
    expect(a1).toBeGreaterThan(audioIdx);
    expect(a1).toBeLessThan(videoIdx);
    expect(v9).toBeGreaterThan(videoIdx);
    expect(lines.filter((l) => l === 'a=candidate:1 1 udp 1 10.0.0.1 5000 typ host')).toHaveLength(1);
    expect(lines.filter((l) => l === 'a=end-of-candidates')).toHaveLength(2);
  });

  test('assembleSdp rejects SDP without media', () => {
    expect(() => sdpUtils.assembleSdp('v=0\r\ns=-\r\n', [])).toThrow(/no media/);
  });
});

// ---- credentials -------------------------------------------------------------

describe('credentials', () => {
  test('usernames come from the digits of the number', () => {
    expect(sipUsernameFor('+1 (555) 000-0001')).toBe('user_15550000001');
  });

  test('passwords are deterministic per secret and user', () => {
    const a = credentialsFor(SECRET, '+15550000001');
    const b = credentialsFor(SECRET, '+15550000001');
    const c = credentialsFor(SECRET, '+15550000002');
    const d = credentialsFor('other', '+15550000001');
    expect(a).toEqual(b);
    expect(a.password).not.toBe(c.password);
    expect(a.password).not.toBe(d.password);
    expect(a.password).toHaveLength(32);
    expect(() => credentialsFor('', '+1')).toThrow(/SIP_GATEWAY_SECRET/);
  });

  test('gateway refuses to start enabled without a secret', () => {
    expect(() => createSipGateway({ enabled: true, secret: '' })).toThrow(/SIP_GATEWAY_SECRET/);
  });

  test('domain defaults to the WebSocket host', () => {
    const { gateway } = makeGateway({ wssUrl: 'wss://pbx.example:8089/ws' });
    expect(gateway.config.domain).toBe('pbx.example');
  });
});

// ---- outbound calls --------------------------------------------------------------

describe('outbound call', () => {
  test('waits for end-of-candidates, then sends one complete SDP in the INVITE', async () => {
    const { gateway, uas } = makeGateway({ iceGatherTimeoutMs: 5000 });
    const session = gateway.placeCall(USER, '*43', { callId: 'c1' });
    const offer = makeOffer();
    session.setOffer(offer);
    const c1 = makeCandidate('10.0.0.1', 5000);
    const c2 = makeCandidate('10.0.0.1', 5001);
    session.addIceCandidate(c1);
    session.addIceCandidate(c2);
    await sleep(30);
    expect(uas).toHaveLength(1);
    expect(uas[0].sentInvites).toHaveLength(0); // still gathering

    session.endOfCandidates();
    const rtc = await once(uas[0], 'invite');
    expect(rtc.target).toBe('sip:*43@pbx.example');
    expect(rtc.options.mediaConstraints).toEqual({ audio: false, video: false });
    expect(rtc.sentSdp).toContain(`a=${c1.candidate}\r\n`);
    expect(rtc.sentSdp).toContain(`a=${c2.candidate}\r\n`);
    expect(rtc.sentSdp).toContain('a=end-of-candidates\r\n');
    expect(rtc.sentSdp).toContain('a=fingerprint:sha-256');
    expect(rtc.sentSdp).not.toMatch(/[^\r]\n/);
    expect(uas[0].credentials).toEqual(credentialsFor(SECRET, USER.phoneNumber));
  });

  test('a null ice-candidate counts as end-of-candidates', async () => {
    const { gateway, uas } = makeGateway({ iceGatherTimeoutMs: 5000 });
    const session = gateway.placeCall(USER, '*43', { callId: 'c-null' });
    session.setOffer(makeOffer());
    session.addIceCandidate(makeCandidate());
    session.addIceCandidate(null);
    const rtc = await once(uas[0], 'invite');
    expect(rtc.sentSdp).toContain('a=end-of-candidates');
  });

  test('sends the INVITE after the gather timeout when the app never signals end-of-candidates', async () => {
    const { gateway, uas } = makeGateway({ iceGatherTimeoutMs: 80 });
    const session = gateway.placeCall(USER, '+15551234567', { callId: 'c2' });
    session.setOffer(makeOffer());
    session.addIceCandidate(makeCandidate());
    await sleep(30);
    expect(uas[0].sentInvites).toHaveLength(0);
    const rtc = await once(uas[0], 'invite');
    expect(rtc.target).toBe('sip:+15551234567@pbx.example');
    expect(rtc.sentSdp).toContain('a=candidate:');
  });

  test('an offer that already carries end-of-candidates goes out immediately', async () => {
    const { gateway, uas } = makeGateway({ iceGatherTimeoutMs: 5000 });
    const session = gateway.placeCall(USER, '*43', { callId: 'c3', sdpOffer: makeOffer({ withCandidates: true }) });
    const rtc = await once(uas[0], 'invite');
    expect(rtc.sentSdp.split('a=end-of-candidates')).toHaveLength(2);
    expect(session.status).toBe('inviting');
  });

  test('maps 180 / 200 / BYE to call-ringing, answer, call-answered, call-ended', async () => {
    const { gateway, uas } = makeGateway();
    const session = gateway.placeCall(USER, '*43', { callId: 'c4', sdpOffer: makeOffer({ withCandidates: true }) });
    const events = recordEvents(session);
    const rtc = await once(uas[0], 'invite');

    rtc.remoteRinging(180);
    const answerSdp = makeAnswer({ withCandidates: true });
    rtc.remoteAnswer(answerSdp);
    rtc.remoteBye();
    await flush();

    expect(events.map((e) => e.event)).toEqual(['call-ringing', 'answer', 'call-answered', 'call-ended', 'closed']);
    expect(events[0].payload).toEqual({ callId: 'c4', sipStatus: 180 });
    expect(events[1].payload).toEqual({ callId: 'c4', sdp: answerSdp, from: '*43' });
    expect(events[2].payload).toEqual({ callId: 'c4', by: '*43', sipStatus: 200 });
    expect(events[3].payload).toEqual({ callId: 'c4', by: '*43', reason: 'Terminated' });
    expect(session.status).toBe('ended');
    expect(session.isActive).toBe(false);
  });

  test('forwards only the first remote answer (early media + 200 OK)', async () => {
    const { gateway, uas } = makeGateway();
    const session = gateway.placeCall(USER, '*43', { callId: 'c4b', sdpOffer: makeOffer({ withCandidates: true }) });
    const events = recordEvents(session);
    const rtc = await once(uas[0], 'invite');
    rtc.emit('sdp', { originator: 'remote', type: 'answer', sdp: 'first' });
    rtc.remoteAnswer('second');
    expect(events.filter((e) => e.event === 'answer')).toHaveLength(1);
    expect(events.find((e) => e.event === 'answer').payload.sdp).toBe('first');
  });

  test('maps SIP failures to call-error with the SIP status', async () => {
    const { gateway, uas } = makeGateway();
    const session = gateway.placeCall(USER, '+15550009999', { callId: 'c5', sdpOffer: makeOffer({ withCandidates: true }) });
    const events = recordEvents(session);
    const rtc = await once(uas[0], 'invite');
    rtc.remoteFail(486, 'Busy Here', 'Busy');
    expect(events.map((e) => e.event)).toEqual(['call-error', 'closed']);
    expect(events[0].payload).toEqual({ callId: 'c5', error: 'Busy', sipStatus: 486, reason: 'Busy Here' });
    expect(session.sipStatus).toBe(486);
  });

  test('terminate before the INVITE closes silently and never dials', async () => {
    const { gateway, uas } = makeGateway({ iceGatherTimeoutMs: 50 });
    const session = gateway.placeCall(USER, '*43', { callId: 'c6' });
    const events = recordEvents(session);
    session.setOffer(makeOffer());
    session.terminate();
    await sleep(120);
    expect(uas[0].sentInvites).toHaveLength(0);
    expect(events.map((e) => e.event)).toEqual(['closed']);
  });

  test('terminate while ringing cancels without reporting an error to the app', async () => {
    const { gateway, uas } = makeGateway();
    const session = gateway.placeCall(USER, '*43', { callId: 'c7', sdpOffer: makeOffer({ withCandidates: true }) });
    const events = recordEvents(session);
    const rtc = await once(uas[0], 'invite');
    rtc.remoteRinging();
    session.terminate();
    expect(rtc.ended).toBe(true);
    expect(events.map((e) => e.event)).toEqual(['call-ringing', 'closed']);
  });

  test('terminate after answer sends BYE and closes', async () => {
    const { gateway, uas } = makeGateway();
    const session = gateway.placeCall(USER, '*43', { callId: 'c8', sdpOffer: makeOffer({ withCandidates: true }) });
    const events = recordEvents(session);
    const rtc = await once(uas[0], 'invite');
    rtc.remoteAnswer(makeAnswer());
    session.terminate();
    expect(rtc.terminatedWith).toEqual({});
    expect(events.map((e) => e.event)).toEqual(['answer', 'call-answered', 'closed']);
  });

  test('an invalid offer fails the call locally', async () => {
    const { gateway } = makeGateway();
    const session = gateway.placeCall(USER, '*43', { callId: 'c9' });
    const events = recordEvents(session);
    session.setOffer('not sdp');
    expect(events[0].event).toBe('call-error');
    expect(events[0].payload.error).toMatch(/Invalid SDP/);
  });

  test('rejects non-SIP destinations and a disabled gateway', () => {
    const { gateway } = makeGateway();
    expect(() => gateway.placeCall(USER, 'bob', { callId: 'x' })).toThrow(/Not a SIP destination/);
    const disabled = createSipGateway({ enabled: false });
    expect(disabled.enabled).toBe(false);
    expect(() => disabled.placeCall(USER, '*43')).toThrow(/disabled/);
    expect(disabled.ensureUserAgent(USER)).rejects.toThrow(/disabled/);
  });
});

// ---- user agents -------------------------------------------------------------------

describe('user agents', () => {
  test('one UA per user, reused across calls, stopped on release', async () => {
    const { gateway, uas } = makeGateway();
    const ua1 = await gateway.ensureUserAgent(USER);
    const ua2 = await gateway.ensureUserAgent(USER);
    await gateway.ensureUserAgent({ id: 'u2', phoneNumber: '+15550000002' });
    expect(ua1).toBe(ua2);
    expect(uas).toHaveLength(2);
    expect(gateway.userAgentCount).toBe(2);
    expect(gateway.releaseUser(USER.id)).toBe(true);
    expect(uas[0].stopped).toBe(true);
    expect(gateway.releaseUser(USER.id)).toBe(false);
    gateway.shutdown();
    expect(uas[1].stopped).toBe(true);
    expect(gateway.userAgentCount).toBe(0);
  });

  test('retries a failed registration once (endpoint just provisioned)', async () => {
    const { gateway, uas } = makeGateway({}, { failRegistrations: 1, failStatus: 404 });
    const ua = await gateway.ensureUserAgent(USER);
    expect(ua.registerCalls).toBe(1);
  }, 10000);

  test('gives up after the retry and reports the call as failed', async () => {
    const { gateway, uas } = makeGateway({}, { failRegistrations: 2, failStatus: 403 });
    const session = gateway.placeCall(USER, '*43', { callId: 'c10', sdpOffer: makeOffer({ withCandidates: true }) });
    const events = recordEvents(session);
    await once(session, 'closed');
    expect(events[0].event).toBe('call-error');
    expect(events[0].payload.error).toBe('SIP gateway unavailable');
    expect(events[0].payload.reason).toMatch(/403/);
    expect(uas[0].stopped).toBe(true);
    expect(gateway.hasUserAgent(USER.id)).toBe(false);
  }, 10000);

  test('a UA factory failure surfaces as call-error', async () => {
    const gateway = createSipGateway({ enabled: true, secret: SECRET, wssUrl: 'ws://x/ws' }, {
      createUserAgent: () => { throw new Error('boom'); }
    });
    const session = gateway.placeCall(USER, '*43', { callId: 'c11', sdpOffer: makeOffer({ withCandidates: true }) });
    const events = recordEvents(session);
    await once(session, 'closed');
    expect(events[0].payload).toMatchObject({ callId: 'c11', error: 'SIP gateway unavailable', reason: 'boom' });
  });
});

// ---- inbound calls ---------------------------------------------------------------

describe('inbound call', () => {
  test('surfaces the INVITE, answers with the app SDP + candidates, maps BYE', async () => {
    const { gateway, uas } = makeGateway({ iceGatherTimeoutMs: 5000 });
    await gateway.ensureUserAgent(USER);
    const incoming = once(gateway, 'incoming-call');
    const offer = makeOffer({ withCandidates: true });
    const rtc = uas[0].incoming('15550000009', offer);
    const session = await incoming;
    const events = recordEvents(session);

    expect(session.direction).toBe('incoming');
    expect(session.callId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
    expect(session.from).toBe('+15550000009');
    expect(session.user).toBe(USER);
    expect(session.remoteSdp).toBe(offer);

    const answer = makeAnswer();
    const cand = makeCandidate('10.0.0.2', 7000);
    session.setAnswer(answer);
    session.addIceCandidate(cand);
    session.endOfCandidates();
    await once(uas[0], 'answered');
    expect(rtc.sentSdp).toContain(`a=${cand.candidate}\r\n`);
    expect(rtc.sentSdp).toContain('a=end-of-candidates');
    expect(session.status).toBe('answered');
    expect(events).toEqual([]); // the app answered, nothing to echo back

    rtc.remoteBye();
    expect(events.map((e) => e.event)).toEqual(['call-ended', 'closed']);
    expect(events[0].payload).toEqual({ callId: session.callId, by: '+15550000009', reason: 'Terminated' });
  });

  test('declining an inbound call rejects it with the given SIP status', async () => {
    const { gateway, uas } = makeGateway();
    await gateway.ensureUserAgent(USER);
    const incoming = once(gateway, 'incoming-call');
    const rtc = uas[0].incoming('webrtc_test', makeOffer({ withCandidates: true }));
    const session = await incoming;
    const events = recordEvents(session);
    expect(session.from).toBe('webrtc_test');
    session.terminate({ statusCode: 486, reason: 'Busy Here' });
    expect(rtc.terminatedWith).toEqual({ status_code: 486, reason_phrase: 'Busy Here' });
    expect(events.map((e) => e.event)).toEqual(['closed']);
  });

  test('an INVITE without SDP is rejected with 488', async () => {
    const { gateway, uas } = makeGateway();
    await gateway.ensureUserAgent(USER);
    const handler = jest.fn();
    gateway.on('incoming-call', handler);
    const rtc = uas[0].incoming('webrtc_test', '');
    await flush();
    expect(handler).not.toHaveBeenCalled();
    expect(rtc.terminatedWith).toEqual({ status_code: 488 });
  });
});

// ---- provisioning ------------------------------------------------------------------

describe('provisioning', () => {
  let dir;
  beforeEach(() => { dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sip-prov-')); });
  afterEach(() => { fs.rmSync(dir, { recursive: true, force: true }); });

  test('renders endpoint, auth and aor sections that use the pjsip.conf templates', () => {
    const block = provisioning.renderUserBlock({ username: 'user_15550000001', password: 'pw', phoneNumber: '+15550000001' });
    expect(block).toContain('[user_15550000001](app-user)');
    expect(block).toContain('auth=user_15550000001');
    expect(block).toContain('aors=user_15550000001');
    expect(block).toContain('callerid="+15550000001" <+15550000001>');
    expect(block).toContain('[user_15550000001](app-auth)\nusername=user_15550000001\npassword=pw');
    expect(block).toContain('[user_15550000001](app-aor)');
  });

  test('writes a new file, is idempotent and replaces a user block in place', async () => {
    const confPath = path.join(dir, 'nested', 'pjsip_users.conf');
    const config = { enabled: true, secret: SECRET, confPath, ami: null, timeoutMs: 1000 };
    const first = await provisioning.provisionSipUser({ phoneNumber: '+15550000001' }, config);
    expect(first).toEqual({ username: 'user_15550000001', changed: true, reloaded: false });
    const again = await provisioning.provisionSipUser({ phoneNumber: '+15550000001' }, config);
    expect(again.changed).toBe(false);
    await provisioning.provisionSipUser({ phoneNumber: '+15550000002' }, config);

    const text = fs.readFileSync(confPath, 'utf8');
    expect(text.startsWith('; pjsip_users.conf - GENERATED')).toBe(true);
    expect((text.match(/;; BEGIN /g) || []).length).toBe(2);
    expect(text).toContain(`password=${credentialsFor(SECRET, '+15550000001').password}`);

    // A changed secret rewrites the block instead of appending a duplicate.
    await provisioning.provisionSipUser({ phoneNumber: '+15550000001' }, { ...config, secret: 'rotated' });
    const rotated = fs.readFileSync(confPath, 'utf8');
    expect((rotated.match(/;; BEGIN user_15550000001/g) || []).length).toBe(1);
    expect(rotated).toContain(`password=${credentialsFor('rotated', '+15550000001').password}`);
    expect(rotated).not.toContain(`password=${credentialsFor(SECRET, '+15550000001').password}`);
  });

  test('is a no-op when disabled and never throws on failure', async () => {
    expect(await provisioning.provisionSipUser({ phoneNumber: '+1' }, { enabled: false })).toEqual({ skipped: true });
    const result = await provisioning.provisionSipUser({ phoneNumber: '+15550000001' }, {
      enabled: true, secret: SECRET, confPath: path.join(dir, 'x'), timeoutMs: 1000,
      ami: { host: '127.0.0.1', port: 1, username: 'u', secret: 's', timeoutMs: 500 }
    });
    expect(result.changed).toBe(true);
    expect(result.reloaded).toBe(false);
    expect(result.error).toMatch(/AMI/);
  });

  test('reads its configuration from the environment', () => {
    const config = provisioning.provisioningConfigFromEnv({
      SIP_ENABLED: 'true', SIP_GATEWAY_SECRET: 's', ASTERISK_USERS_CONF: '/tmp/u.conf',
      ASTERISK_AMI_HOST: 'asterisk', ASTERISK_AMI_PORT: '5039', ASTERISK_AMI_USER: 'gw', ASTERISK_AMI_SECRET: 'x'
    });
    expect(config).toMatchObject({ enabled: true, confPath: '/tmp/u.conf', ami: { host: 'asterisk', port: 5039, username: 'gw', secret: 'x' } });
    expect(provisioning.provisioningConfigFromEnv({}).ami).toBeNull();
  });
});
