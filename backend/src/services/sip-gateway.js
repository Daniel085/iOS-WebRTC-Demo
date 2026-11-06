/**
 * SIP Gateway
 *
 * The Node server acts as the SIP user agent on behalf of each app user
 * (docs/SIP_INTEGRATION.md, "Target architecture"). The app keeps speaking the
 * existing Socket.IO events; this module owns one JsSIP UA per app user,
 * connected to Asterisk over SIP/WebSocket, and translates:
 *
 *   app  call-initiate + offer (+ ice-candidate…)  ->  INVITE with ONE complete SDP
 *   SIP  180/183                                    ->  call-ringing
 *   SIP  200 OK {sdp}                               ->  answer {sdp}, then call-answered
 *   app  call-end                                   ->  CANCEL / BYE
 *   SIP  BYE                                        ->  call-ended
 *   SIP  4xx/5xx/6xx                                ->  call-error {sipStatus}
 *   SIP  INVITE (inbound)                           ->  'incoming-call' (gateway event) -> app incoming-call + offer
 *
 * No media touches Node: the SDP is relayed unchanged, so RTP/DTLS flows
 * app <-> Asterisk directly. JsSIP needs an RTCPeerConnection to exist; the
 * pass-through shim in ./sip/passthrough-peer-connection.js provides one.
 *
 * Configuration (env):
 *   SIP_ENABLED=true                     turn the gateway on
 *   ASTERISK_WSS_URL=wss://host:8089/ws  SIP over WebSocket endpoint (ws:// allowed for a local/docker-internal Asterisk)
 *   ASTERISK_DOMAIN=host                 SIP domain for user URIs and dialled targets (defaults to the URL host)
 *   SIP_GATEWAY_SECRET=…                 HMAC key the per-user SIP passwords are derived from (keep it secret)
 *   ASTERISK_TLS_INSECURE=true           accept Asterisk's self-signed certificate (prototype only)
 *   SIP_ICE_GATHER_TIMEOUT_MS=2000       how long to wait for the app's ICE candidates before sending the INVITE
 *   SIP_REGISTER_TIMEOUT_MS=10000        how long a user's REGISTER may take before an outbound call fails
 *   SIP_REGISTER_EXPIRES=300             registration lifetime requested from Asterisk
 *   SIP_DEBUG=true                       enable JsSIP's own debug logging
 */

const EventEmitter = require('events');
const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');

const logger = require('../utils/logger');
const sdpUtils = require('./sip/sdp');
const { installNodeWebRtcShims } = require('./sip/passthrough-peer-connection');
const { NodeWebSocketInterface } = require('./sip/node-websocket');

/** Socket.IO events a SipCallSession can emit toward the app. */
const SIP_EVENTS = ['call-ringing', 'answer', 'call-answered', 'call-ended', 'call-error'];

const toInt = (value, fallback) => {
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
};

function configFromEnv(env = process.env) {
  const wssUrl = env.ASTERISK_WSS_URL || 'wss://localhost:8089/ws';
  let domainFromUrl = 'localhost';
  try { domainFromUrl = new URL(wssUrl).hostname; } catch (_) { /* validated later */ }
  return {
    enabled: env.SIP_ENABLED === 'true',
    wssUrl,
    domain: env.ASTERISK_DOMAIN || domainFromUrl,
    secret: env.SIP_GATEWAY_SECRET || '',
    insecureTls: env.ASTERISK_TLS_INSECURE === 'true',
    iceGatherTimeoutMs: toInt(env.SIP_ICE_GATHER_TIMEOUT_MS, 2000),
    registerTimeoutMs: toInt(env.SIP_REGISTER_TIMEOUT_MS, 10000),
    registerExpires: toInt(env.SIP_REGISTER_EXPIRES, 300),
    debug: env.SIP_DEBUG === 'true'
  };
}

/** PJSIP endpoint name for an app user: +1 555 000 0001 -> user_15550000001 */
function sipUsernameFor(phoneNumber) {
  return `user_${String(phoneNumber).replace(/\D/g, '')}`;
}

/**
 * Credentials are derived, not stored: HMAC(secret, username). The backend
 * and the provisioning step therefore always agree, even after an in-memory
 * restart, and nothing secret has to be persisted next to the user.
 */
function credentialsFor(secret, phoneNumber) {
  if (!secret) throw new Error('SIP_GATEWAY_SECRET is required to derive SIP credentials');
  const username = sipUsernameFor(phoneNumber);
  const password = crypto.createHmac('sha256', secret).update(username).digest('base64url').slice(0, 32);
  return { username, password };
}

/**
 * Default UA factory: a real JsSIP.UA over our ws-based socket.
 */
function createJsSipUserAgent({ config, credentials }) {
  // Required lazily so that the shims are installed before JsSIP looks for WebRTC.
  const JsSIP = require('jssip');
  if (config.debug) JsSIP.debug.enable('JsSIP:*');

  const socket = new NodeWebSocketInterface(config.wssUrl, { rejectUnauthorized: !config.insecureTls });
  return new JsSIP.UA({
    sockets: [socket],
    uri: `sip:${credentials.username}@${config.domain}`,
    password: credentials.password,
    register: true,
    register_expires: config.registerExpires,
    session_timers: false,
    user_agent: 'WebRTCDialer-Gateway/1.0',
    connection_recovery_min_interval: 2,
    connection_recovery_max_interval: 30
  });
}

/**
 * One call leg between an app user and Asterisk.
 *
 * Emits the Socket.IO events listed in SIP_EVENTS with ready-to-send payloads,
 * plus an internal 'closed' event (whatever the reason) so the signaling
 * server can drop its bookkeeping.
 */
class SipCallSession extends EventEmitter {
  constructor(gateway, { callId, direction, user, destination, from, hasVideo = false, rtcSession = null, remoteSdp = null }) {
    super();
    this.gateway = gateway;
    this.callId = callId;
    this.direction = direction; // 'outgoing' (app -> SIP) | 'incoming' (SIP -> app)
    this.user = user;           // { id, phoneNumber }
    this.destination = destination || null;
    this.from = from || null;
    this.hasVideo = hasVideo;
    this.rtcSession = rtcSession;
    this.remoteSdp = remoteSdp; // inbound INVITE body
    this.localSdp = null;       // complete SDP sent to Asterisk
    this.status = 'new';        // new | gathering | inviting | ringing | answered | ended | failed
    this.sipStatus = null;

    this._localSdpBase = null;
    this._candidates = [];
    this._endOfCandidates = false;
    this._gatherTimer = null;
    this._localSent = false;
    this._remoteAnswerForwarded = false;
    this._closed = false;
  }

  /** The other party, as the app should see it. */
  get peer() {
    return this.direction === 'outgoing' ? this.destination : this.from;
  }

  get isActive() {
    return !this._closed;
  }

  // ---- SDP from the app ---------------------------------------------------

  /** Outgoing call: the app's SDP offer (may or may not contain candidates yet). */
  setOffer(sdp) {
    if (this.direction !== 'outgoing') {
      logger.warn(`SIP call ${this.callId}: ignoring offer from the app on an inbound call (renegotiation not supported yet)`);
      return;
    }
    this._setLocalBase(sdp);
  }

  /** Incoming call: the app's SDP answer. */
  setAnswer(sdp) {
    if (this.direction !== 'incoming') {
      logger.warn(`SIP call ${this.callId}: ignoring answer from the app on an outbound call`);
      return;
    }
    this._setLocalBase(sdp);
  }

  /** Buffer a trickled ICE candidate; null/empty means end-of-candidates. */
  addIceCandidate(candidate) {
    if (this._localSent || this._closed) return;
    if (sdpUtils.isEndOfCandidates(candidate)) {
      this.endOfCandidates();
      return;
    }
    this._candidates.push(candidate);
  }

  endOfCandidates() {
    if (this._localSent || this._closed) return;
    this._endOfCandidates = true;
    if (this._localSdpBase) this._finalizeLocalSdp();
  }

  _setLocalBase(sdp) {
    if (this._localSent || this._closed) return;
    if (typeof sdp !== 'string' || !/^m=/m.test(sdp)) {
      this._fail('Invalid SDP from app', { local: true });
      return;
    }
    this._localSdpBase = sdp;
    this.status = 'gathering';

    if (this._endOfCandidates || sdpUtils.hasEndOfCandidates(sdp)) {
      this._finalizeLocalSdp();
      return;
    }
    // No trickle ICE toward Asterisk: give the app a bounded time to finish
    // gathering, then send what we have.
    const timeout = this.gateway.config.iceGatherTimeoutMs;
    this._gatherTimer = setTimeout(() => this._finalizeLocalSdp(), timeout);
    if (typeof this._gatherTimer.unref === 'function') this._gatherTimer.unref();
  }

  _finalizeLocalSdp() {
    if (this._gatherTimer) {
      clearTimeout(this._gatherTimer);
      this._gatherTimer = null;
    }
    if (this._localSent || this._closed) return;
    this._localSent = true;

    try {
      this.localSdp = sdpUtils.assembleSdp(this._localSdpBase, this._candidates);
    } catch (error) {
      this._fail(`Could not build SDP: ${error.message}`, { local: true });
      return;
    }

    if (this.direction === 'outgoing') this._sendInvite();
    else this._sendAnswer();
  }

  // ---- SIP side -----------------------------------------------------------

  async _sendInvite() {
    this.status = 'inviting';
    let ua;
    try {
      ua = await this.gateway.ensureUserAgent(this.user);
    } catch (error) {
      logger.error(`SIP call ${this.callId}: user agent unavailable: ${error.message}`);
      this._fail('SIP gateway unavailable', { detail: error.message });
      return;
    }
    if (this._closed) return;

    const target = sdpUtils.sipTargetFor(this.destination, this.gateway.config.domain);
    logger.info(`SIP call ${this.callId}: INVITE ${target} for ${this.user.phoneNumber}`);

    try {
      this.rtcSession = ua.call(target, {
        mediaConstraints: { audio: false, video: false },
        pcConfig: { iceServers: [] },
        extraHeaders: [`X-App-Call-Id: ${this.callId}`],
        eventHandlers: this._rtcEventHandlers()
      });
    } catch (error) {
      logger.error(`SIP call ${this.callId}: ua.call() failed: ${error.message}`);
      this._fail('Could not place SIP call', { detail: error.message });
    }
  }

  _sendAnswer() {
    if (!this.rtcSession) {
      this._fail('No SIP session to answer', { local: true });
      return;
    }
    logger.info(`SIP call ${this.callId}: sending 200 OK for ${this.user.phoneNumber}`);
    try {
      this.rtcSession.answer({
        mediaConstraints: { audio: false, video: false },
        pcConfig: { iceServers: [] }
      });
    } catch (error) {
      logger.error(`SIP call ${this.callId}: answer() failed: ${error.message}`);
      this._fail('Could not answer SIP call', { detail: error.message });
    }
  }

  /** JsSIP RTCSession event handlers, shared by both directions. */
  _rtcEventHandlers() {
    return {
      peerconnection: (e) => {
        // The pass-through peer connection returns this SDP from createOffer()/createAnswer().
        if (this.localSdp && e.peerconnection && typeof e.peerconnection.setPendingLocalSdp === 'function') {
          e.peerconnection.setPendingLocalSdp(this.localSdp);
        }
      },
      sdp: (e) => this._onSdp(e),
      progress: (e) => this._onProgress(e),
      accepted: (e) => this._onAccepted(e),
      ended: (e) => this._onEnded(e),
      failed: (e) => this._onFailed(e)
    };
  }

  /** Attach the handlers to an existing (inbound) RTCSession. */
  bindRtcSession(rtcSession) {
    this.rtcSession = rtcSession;
    const handlers = this._rtcEventHandlers();
    for (const [event, handler] of Object.entries(handlers)) rtcSession.on(event, handler);
  }

  _onSdp(e) {
    if (!e || e.originator !== 'remote') return;
    if (e.type === 'answer') {
      if (this._remoteAnswerForwarded) {
        logger.debug(`SIP call ${this.callId}: additional remote answer ignored (early media/refresh)`);
        return;
      }
      this._remoteAnswerForwarded = true;
      this.emit('answer', { callId: this.callId, sdp: e.sdp, from: this.peer });
    } else if (e.type === 'offer' && this.direction === 'incoming' && !this.rtcSession?.isEstablished?.()) {
      // Initial inbound offer: already captured as remoteSdp.
    } else {
      logger.info(`SIP call ${this.callId}: re-INVITE from Asterisk answered with the current SDP`);
    }
  }

  _onProgress(e) {
    if (this.direction !== 'outgoing') return;
    this.status = 'ringing';
    const sipStatus = e && e.response ? e.response.status_code : 180;
    this.emit('call-ringing', { callId: this.callId, sipStatus });
  }

  _onAccepted(e) {
    this.status = 'answered';
    if (this.direction !== 'outgoing') return; // the app answered; it already knows
    const sipStatus = e && e.response ? e.response.status_code : 200;
    this.sipStatus = sipStatus;
    this.emit('call-answered', { callId: this.callId, by: this.peer, sipStatus });
  }

  _onEnded(e) {
    this.status = 'ended';
    const originator = e ? e.originator : 'remote';
    if (originator !== 'local') {
      this.emit('call-ended', { callId: this.callId, by: this.peer, reason: (e && e.cause) || 'ended' });
    }
    this._close();
  }

  _onFailed(e) {
    this.status = 'failed';
    const cause = (e && e.cause) || 'failed';
    const originator = e ? e.originator : 'remote';
    const message = e && e.message;
    const sipStatus = message && typeof message.status_code === 'number' ? message.status_code : null;
    const reason = message && message.reason_phrase ? message.reason_phrase : null;
    this.sipStatus = sipStatus;

    if (originator === 'local' && (cause === 'Canceled' || cause === 'Rejected')) {
      // The app hung up / declined before the call was established: nothing to report back.
      this._close();
      return;
    }
    this.emit('call-error', {
      callId: this.callId,
      error: cause,
      sipStatus,
      reason
    });
    this._close();
  }

  /**
   * Hang up / cancel / decline from the app side.
   * @param {object} [options]
   * @param {number} [options.statusCode]  SIP status for declining an inbound call (486 busy, 603 decline)
   */
  terminate(options = {}) {
    if (this._closed) return;
    if (this._gatherTimer) {
      clearTimeout(this._gatherTimer);
      this._gatherTimer = null;
    }
    const rtcSession = this.rtcSession;
    if (rtcSession && typeof rtcSession.isEnded === 'function' && !rtcSession.isEnded()) {
      const opts = {};
      if (options.statusCode) opts.status_code = options.statusCode;
      if (options.reason) opts.reason_phrase = options.reason;
      try {
        rtcSession.terminate(opts); // 'failed'/'ended' handlers close this session
        return;
      } catch (error) {
        logger.warn(`SIP call ${this.callId}: terminate() failed: ${error.message}`);
      }
    }
    this.status = 'ended';
    this._close();
  }

  _fail(error, { local = false, detail = null } = {}) {
    this.status = 'failed';
    this.emit('call-error', { callId: this.callId, error, sipStatus: null, reason: detail });
    if (local && this.rtcSession && typeof this.rtcSession.isEnded === 'function' && !this.rtcSession.isEnded()) {
      try { this.rtcSession.terminate({ status_code: 500 }); } catch (_) { /* best effort */ }
    }
    this._close();
  }

  _close() {
    if (this._closed) return;
    this._closed = true;
    if (this._gatherTimer) {
      clearTimeout(this._gatherTimer);
      this._gatherTimer = null;
    }
    this.emit('closed', { callId: this.callId, status: this.status });
  }
}

class SipGateway extends EventEmitter {
  /**
   * @param {object} config   see configFromEnv()
   * @param {object} [deps]
   * @param {Function} [deps.createUserAgent]  ({config, user, credentials}) => UA (JsSIP.UA-compatible); tests inject a fake
   */
  constructor(config, deps = {}) {
    super();
    this.config = { ...configFromEnv({}), ...config };
    if (!config.domain) {
      try { this.config.domain = new URL(this.config.wssUrl).hostname; } catch (_) { /* validated by the socket */ }
    }
    this.enabled = !!this.config.enabled;
    this._createUserAgent = deps.createUserAgent || createJsSipUserAgent;
    this._userAgents = new Map(); // userId -> { ua, ready: Promise<UA>, user }
    this._shuttingDown = false;

    if (this.enabled) {
      if (!this.config.secret) {
        throw new Error('SIP_GATEWAY_SECRET must be set when SIP_ENABLED=true');
      }
      installNodeWebRtcShims();
      logger.info(`SIP gateway enabled: ${this.config.wssUrl} (domain ${this.config.domain})`);
    }
  }

  isSipDestination(to) {
    return sdpUtils.isSipDestination(to);
  }

  credentialsFor(phoneNumber) {
    return credentialsFor(this.config.secret, phoneNumber);
  }

  /** Number of users with a live UA (for health/diagnostics). */
  get userAgentCount() {
    return this._userAgents.size;
  }

  /**
   * Get (or create and register) the SIP user agent for an app user.
   * Resolves with the UA once it is registered with Asterisk.
   */
  ensureUserAgent(user) {
    if (!this.enabled) return Promise.reject(new Error('SIP gateway is disabled'));
    if (!user || !user.id || !user.phoneNumber) return Promise.reject(new Error('ensureUserAgent: user with id and phoneNumber required'));

    const existing = this._userAgents.get(user.id);
    if (existing) return existing.ready;

    let credentials;
    let ua;
    try {
      credentials = this.credentialsFor(user.phoneNumber);
      ua = this._createUserAgent({ config: this.config, user, credentials });
    } catch (error) {
      return Promise.reject(error);
    }
    const entry = { ua, user, ready: null, registered: false };
    this._userAgents.set(user.id, entry);

    entry.ready = new Promise((resolve, reject) => {
      let settled = false;
      let retried = false;
      const finish = (fn, value) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        fn(value);
      };
      const timer = setTimeout(() => {
        finish(reject, new Error(`SIP registration of ${credentials.username} timed out after ${this.config.registerTimeoutMs} ms`));
      }, this.config.registerTimeoutMs);
      if (typeof timer.unref === 'function') timer.unref();

      ua.on('registered', () => {
        entry.registered = true;
        logger.info(`SIP registered: ${credentials.username} (${user.phoneNumber})`);
        finish(resolve, ua);
      });
      ua.on('unregistered', () => {
        entry.registered = false;
      });
      ua.on('registrationFailed', (e) => {
        const status = e && e.response ? e.response.status_code : null;
        const cause = (e && e.cause) || 'unknown';
        logger.warn(`SIP registration failed for ${credentials.username}: ${status || ''} ${cause}`.trim());
        // The endpoint may have been provisioned a moment ago and Asterisk is
        // still reloading: retry once before giving up.
        if (!settled && !retried && (status === 401 || status === 403 || status === 404)) {
          retried = true;
          setTimeout(() => { if (!settled) safely(() => ua.register()); }, 1500);
          return;
        }
        finish(reject, new Error(`SIP registration failed (${status || cause})`));
      });
      ua.on('disconnected', (e) => {
        const reason = e && (e.reason || (e.error && e.error.message)) ? (e.reason || e.error.message) : 'transport closed';
        logger.warn(`SIP transport disconnected for ${credentials.username}: ${reason}`);
        if (!settled && !ua.isConnected?.()) {
          // JsSIP keeps retrying the WebSocket on its own; fail the first call
          // quickly instead of waiting for the registration timeout.
          finish(reject, new Error(`SIP transport unavailable at ${this.config.wssUrl}: ${reason}`));
        }
      });
      ua.on('newRTCSession', (e) => this._onNewRTCSession(user, e));

      try {
        ua.start();
      } catch (error) {
        finish(reject, error);
      }
    });

    entry.ready.catch(() => {
      // A UA that never became usable must not be reused.
      if (this._userAgents.get(user.id) === entry) {
        this._userAgents.delete(user.id);
        safely(() => ua.stop());
      }
    });

    return entry.ready;
  }

  /** Stop the user's UA (unregisters from Asterisk). Called when the app disconnects. */
  releaseUser(userId) {
    const entry = this._userAgents.get(userId);
    if (!entry) return false;
    this._userAgents.delete(userId);
    logger.info(`SIP unregistering ${sipUsernameFor(entry.user.phoneNumber)}`);
    safely(() => entry.ua.stop());
    return true;
  }

  hasUserAgent(userId) {
    return this._userAgents.has(userId);
  }

  /**
   * Place an outbound call. Returns the session synchronously; the INVITE goes
   * out once the app's offer and ICE candidates are complete (or sdpOffer is
   * already complete).
   */
  placeCall(user, destination, { callId = `sip-${uuidv4()}`, hasVideo = false, sdpOffer = null } = {}) {
    if (!this.enabled) throw new Error('SIP gateway is disabled');
    if (!this.isSipDestination(destination)) throw new Error(`Not a SIP destination: ${destination}`);

    const session = new SipCallSession(this, { callId, direction: 'outgoing', user, destination, hasVideo });
    // Start connecting/registering now so the INVITE is not delayed by it.
    this.ensureUserAgent(user).catch(() => { /* reported when the INVITE is attempted */ });
    if (sdpOffer) session.setOffer(sdpOffer);
    return session;
  }

  _onNewRTCSession(user, e) {
    if (!e || e.originator !== 'remote' || !e.session) return; // our own outgoing call
    const rtcSession = e.session;
    const remoteUser = rtcSession.remote_identity && rtcSession.remote_identity.uri ? rtcSession.remote_identity.uri.user : null;
    const from = sdpUtils.dialableFromSipUser(remoteUser);
    const remoteSdp = e.request ? e.request.body : null;

    if (!remoteSdp) {
      logger.warn(`SIP inbound INVITE for ${user.phoneNumber} without SDP rejected (late offer not supported)`);
      safely(() => rtcSession.terminate({ status_code: 488 }));
      return;
    }

    const session = new SipCallSession(this, {
      callId: `sip-${uuidv4()}`,
      direction: 'incoming',
      user,
      from,
      remoteSdp,
      rtcSession
    });
    session.bindRtcSession(rtcSession);
    logger.info(`SIP inbound call ${session.callId}: ${from} -> ${user.phoneNumber}`);
    this.emit('incoming-call', session);
  }

  /** Stop every UA (process shutdown). */
  shutdown() {
    this._shuttingDown = true;
    for (const [userId] of this._userAgents) this.releaseUser(userId);
  }
}

function safely(fn) {
  try { fn(); } catch (error) { logger.debug(`SIP gateway: ignored error ${error.message}`); }
}

let defaultGateway = null;

/** Process-wide gateway built from the environment (lazily). */
function getGateway() {
  if (!defaultGateway) defaultGateway = new SipGateway(configFromEnv());
  return defaultGateway;
}

function createSipGateway(config, deps) {
  return new SipGateway(config, deps);
}

/** Tests only: forget the process-wide instance. */
function _resetDefaultGateway() {
  if (defaultGateway) defaultGateway.shutdown();
  defaultGateway = null;
}

module.exports = {
  SipGateway,
  SipCallSession,
  SIP_EVENTS,
  configFromEnv,
  credentialsFor,
  sipUsernameFor,
  createJsSipUserAgent,
  createSipGateway,
  getGateway,
  _resetDefaultGateway
};
