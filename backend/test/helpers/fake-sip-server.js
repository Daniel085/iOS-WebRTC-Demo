/**
 * A small SIP-over-WebSocket server that behaves like Asterisk's PJSIP WebSocket
 * transport closely enough to drive the real JsSIP stack in tests:
 *
 *   - REGISTER: 401 digest challenge, then 200 OK (credentials checked)
 *   - INVITE:   401 challenge (like Asterisk), 100 Trying, optional 180 Ringing,
 *               then 200 OK with SDP (or a configured failure such as 486)
 *   - ACK / BYE / CANCEL handled; the server can also send BYE (remote hangup)
 *     and INVITE a registered client (inbound call)
 *
 * It is NOT a general SIP implementation: one dialog per Call-ID, no
 * retransmissions, no Record-Route.
 */
const EventEmitter = require('events');
const crypto = require('crypto');
const http = require('http');
const { WebSocketServer } = require('ws');

const md5 = (s) => crypto.createHash('md5').update(s).digest('hex');
const rand = (n = 8) => crypto.randomBytes(n).toString('hex');

function parseSip(text) {
  const sep = text.indexOf('\r\n\r\n');
  const head = sep === -1 ? text : text.slice(0, sep);
  const body = sep === -1 ? '' : text.slice(sep + 4);
  const lines = head.split('\r\n');
  const startLine = lines.shift();
  const headers = {};
  for (const line of lines) {
    const i = line.indexOf(':');
    if (i === -1) continue;
    const name = line.slice(0, i).trim().toLowerCase();
    const value = line.slice(i + 1).trim();
    (headers[name] = headers[name] || []).push(value);
  }
  const msg = { startLine, headers, body, raw: text };
  const h = (name) => (headers[name] ? headers[name][0] : undefined);
  msg.get = h;
  if (startLine.startsWith('SIP/2.0')) {
    msg.isResponse = true;
    const m = /^SIP\/2\.0 (\d{3}) ?(.*)$/.exec(startLine);
    msg.status = parseInt(m[1], 10);
    msg.reason = m[2];
  } else {
    const m = /^(\S+) (\S+) SIP\/2\.0$/.exec(startLine);
    msg.method = m ? m[1] : null;
    msg.uri = m ? m[2] : null;
  }
  msg.callId = h('call-id');
  msg.cseq = h('cseq');
  msg.cseqMethod = msg.cseq ? msg.cseq.split(/\s+/)[1] : null;
  msg.from = h('from');
  msg.to = h('to');
  msg.fromTag = (/;tag=([^;>\s]+)/.exec(msg.from || '') || [])[1];
  msg.toTag = (/;tag=([^;>\s]+)/.exec(msg.to || '') || [])[1];
  msg.contact = h('contact');
  msg.contactUri = (/<([^>]+)>/.exec(msg.contact || '') || [])[1] || msg.contact;
  return msg;
}

function parseAuthParams(header) {
  const params = {};
  const re = /(\w+)=(?:"([^"]*)"|([^,\s]*))/g;
  let m;
  while ((m = re.exec(header.replace(/^Digest\s+/i, '')))) params[m[1]] = m[2] !== undefined ? m[2] : m[3];
  return params;
}

class FakeSipServer extends EventEmitter {
  /**
   * @param {object} options
   * @param {string} [options.realm='fake.local']
   * @param {Object<string,string>} [options.users]  username -> password
   */
  constructor({ realm = 'fake.local', users = {} } = {}) {
    super();
    this.realm = realm;
    this.users = { ...users };
    this.registrations = new Map(); // username -> { ws, contactUri, aor }
    this.calls = new Map();         // callId -> dialog state
    this.requests = [];             // every request received (for assertions)
    this.inviteBehaviour = { status: 200, ringing: true, ringDelayMs: 20, answerDelayMs: 40, challenge: true };
    this.answerSdp = null;          // SDP the server answers with (set by tests)
    this.port = null;
    this._ws = null;
    this._http = null;
    this._cseq = 1;
  }

  async start(port = 0) {
    this._http = http.createServer();
    this._wss = new WebSocketServer({ server: this._http, handleProtocols: () => 'sip' });
    this._wss.on('connection', (ws) => {
      ws.on('message', (data) => this._onMessage(ws, data.toString('utf8')));
      ws.on('close', () => {
        for (const [user, reg] of this.registrations) if (reg.ws === ws) this.registrations.delete(user);
      });
    });
    await new Promise((resolve) => this._http.listen(port, '127.0.0.1', resolve));
    this.port = this._http.address().port;
    return this;
  }

  get url() { return `ws://127.0.0.1:${this.port}/ws`; }

  async stop() {
    for (const client of this._wss.clients) client.terminate();
    await new Promise((resolve) => this._wss.close(() => resolve()));
    await new Promise((resolve) => this._http.close(() => resolve()));
  }

  // ---- helpers -----------------------------------------------------------

  _send(ws, text) {
    if (ws.readyState === ws.OPEN) ws.send(text);
  }

  _response(req, status, reason, { headers = [], body = '', toTag } = {}) {
    const to = req.toTag || !toTag ? req.to : `${req.to};tag=${toTag}`;
    const lines = [
      `SIP/2.0 ${status} ${reason}`,
      ...(req.headers.via || []).map((v) => `Via: ${v}`),
      `From: ${req.from}`,
      `To: ${to}`,
      `Call-ID: ${req.callId}`,
      `CSeq: ${req.cseq}`,
      ...headers,
      `Content-Length: ${Buffer.byteLength(body)}`,
      '',
      body
    ];
    return lines.join('\r\n');
  }

  _request(method, uri, { headers = [], body = '' }) {
    const lines = [
      `${method} ${uri} SIP/2.0`,
      `Via: SIP/2.0/WS ${this.realm};branch=z9hG4bK${rand()}`,
      'Max-Forwards: 70',
      ...headers,
      `Content-Length: ${Buffer.byteLength(body)}`,
      '',
      body
    ];
    return lines.join('\r\n');
  }

  _challenge(ws, req, method) {
    const nonce = rand();
    this._nonces = this._nonces || new Set();
    this._nonces.add(nonce);
    const header = `WWW-Authenticate: Digest realm="${this.realm}",nonce="${nonce}",algorithm=MD5,qop="auth"`;
    this._send(ws, this._response(req, 401, 'Unauthorized', { headers: [header], toTag: rand(4) }));
    this.emit('challenge', { method });
  }

  _authorized(req) {
    const header = req.get('authorization');
    if (!header) return null;
    const p = parseAuthParams(header);
    const password = this.users[p.username];
    if (!password || !this._nonces || !this._nonces.has(p.nonce)) return null;
    const ha1 = md5(`${p.username}:${p.realm}:${password}`);
    const ha2 = md5(`${req.method}:${p.uri}`);
    const expected = p.qop
      ? md5(`${ha1}:${p.nonce}:${p.nc}:${p.cnonce}:${p.qop}:${ha2}`)
      : md5(`${ha1}:${p.nonce}:${ha2}`);
    return expected === p.response ? p.username : null;
  }

  // ---- inbound messages --------------------------------------------------

  _onMessage(ws, text) {
    if (!text.trim()) return; // JsSIP keep-alive CRLF
    const msg = parseSip(text);
    if (msg.isResponse) return this._onResponse(ws, msg);
    this.requests.push(msg);
    this.emit('request', msg);
    switch (msg.method) {
      case 'REGISTER': return this._onRegister(ws, msg);
      case 'INVITE': return this._onInvite(ws, msg);
      case 'ACK': this.emit('ack', msg); return undefined;
      case 'BYE': return this._onBye(ws, msg);
      case 'CANCEL': return this._onCancel(ws, msg);
      case 'OPTIONS': return this._send(ws, this._response(msg, 200, 'OK', { toTag: rand(4) }));
      default: return this._send(ws, this._response(msg, 405, 'Method Not Allowed', { toTag: rand(4) }));
    }
  }

  _onRegister(ws, req) {
    const user = this._authorized(req);
    if (!user) return this._challenge(ws, req, 'REGISTER');
    const expires = req.get('expires') || '300';
    this.registrations.set(user, { ws, contactUri: req.contactUri, aor: req.to });
    this._send(ws, this._response(req, 200, 'OK', {
      headers: [`Contact: ${req.contact};expires=${expires}`, `Expires: ${expires}`],
      toTag: rand(4)
    }));
    this.emit('register', { user, expires: parseInt(expires, 10) });
  }

  _onInvite(ws, req) {
    const b = this.inviteBehaviour;
    if (b.challenge && !req.get('authorization')) return this._challenge(ws, req, 'INVITE');
    const user = b.challenge ? this._authorized(req) : 'anonymous';
    if (!user) return this._send(ws, this._response(req, 403, 'Forbidden', { toTag: rand(4) }));

    const call = {
      callId: req.callId,
      invite: req,
      ws,
      localTag: rand(4),
      remoteTag: req.fromTag,
      remoteContact: req.contactUri,
      state: 'proceeding',
      user,
      uri: req.uri
    };
    this.calls.set(req.callId, call);
    this.emit('invite', { call, request: req, sdp: req.body, uri: req.uri, user });

    this._send(ws, this._response(req, 100, 'Trying'));
    const contact = `Contact: <sip:fake@${this.realm};transport=ws>`;

    const finish = () => {
      if (call.state === 'cancelled') return;
      if (b.status >= 300) {
        call.state = 'failed';
        this._send(ws, this._response(req, b.status, b.reason || 'Failure', { toTag: call.localTag }));
        this.calls.delete(req.callId);
        return;
      }
      call.state = 'answered';
      const body = this.answerSdp || defaultAnswerSdp();
      this._send(ws, this._response(req, 200, 'OK', {
        headers: [contact, 'Content-Type: application/sdp'],
        body,
        toTag: call.localTag
      }));
      this.emit('answered', { call, sdp: body });
    };

    if (b.ringing) {
      setTimeout(() => {
        if (call.state !== 'proceeding') return;
        call.state = 'ringing';
        this._send(ws, this._response(req, 180, 'Ringing', { headers: [contact], toTag: call.localTag }));
        setTimeout(finish, b.answerDelayMs);
      }, b.ringDelayMs);
    } else {
      setTimeout(finish, b.answerDelayMs);
    }
  }

  _onBye(ws, req) {
    this._send(ws, this._response(req, 200, 'OK'));
    const call = this.calls.get(req.callId);
    if (call) call.state = 'ended';
    this.calls.delete(req.callId);
    this.emit('bye', { callId: req.callId, request: req });
  }

  _onCancel(ws, req) {
    this._send(ws, this._response(req, 200, 'OK'));
    const call = this.calls.get(req.callId);
    if (call && call.invite) {
      call.state = 'cancelled';
      this._send(ws, this._response(call.invite, 487, 'Request Terminated', { toTag: call.localTag }));
      this.calls.delete(req.callId);
    }
    this.emit('cancel', { callId: req.callId });
  }

  _onResponse(ws, res) {
    this.emit('response', res);
    const call = this.calls.get(res.callId);
    if (!call || call.direction !== 'outbound') return;
    if (res.cseqMethod === 'INVITE') {
      if (res.status >= 200 && res.status < 300) {
        call.remoteTag = res.toTag;
        call.remoteContact = res.contactUri;
        call.state = 'answered';
        call.answerSdp = res.body;
        // ACK the 200
        this._send(ws, this._request('ACK', call.remoteContact, {
          headers: [
            `From: ${call.fromHeader}`,
            `To: ${res.to}`,
            `Call-ID: ${call.callId}`,
            `CSeq: ${call.cseq} ACK`
          ]
        }));
        this.emit('outbound-answered', { call, sdp: res.body });
      } else if (res.status >= 300) {
        call.state = 'failed';
        this._send(ws, this._request('ACK', call.uri, {
          headers: [`From: ${call.fromHeader}`, `To: ${res.to}`, `Call-ID: ${call.callId}`, `CSeq: ${call.cseq} ACK`]
        }));
        this.calls.delete(call.callId);
        this.emit('outbound-failed', { call, status: res.status });
      } else if (res.status > 100) {
        this.emit('outbound-progress', { call, status: res.status });
      }
    } else if (res.cseqMethod === 'BYE') {
      this.calls.delete(res.callId);
    }
  }

  // ---- actions driven by tests ------------------------------------------

  /** Send BYE for an established call (remote hangup). */
  hangup(callId) {
    const call = this.calls.get(callId);
    if (!call) throw new Error(`fake SIP server: unknown call ${callId}`);
    const invite = call.invite;
    const fromHeader = call.direction === 'outbound' ? call.fromHeader : `${invite.to};tag=${call.localTag}`;
    const toHeader = call.direction === 'outbound' ? `${call.toHeader};tag=${call.remoteTag}` : invite.from;
    this._send(call.ws, this._request('BYE', call.remoteContact, {
      headers: [`From: ${fromHeader}`, `To: ${toHeader}`, `Call-ID: ${callId}`, `CSeq: ${++this._cseq} BYE`]
    }));
    call.state = 'ended';
    this.calls.delete(callId);
  }

  /** Send an INVITE to a registered user (inbound call). Returns the Call-ID. */
  invite(username, { from = 'webrtc_test', displayName = 'WebRTC Test', sdp = defaultAnswerSdp() } = {}) {
    const reg = this.registrations.get(username);
    if (!reg) throw new Error(`fake SIP server: ${username} is not registered`);
    const callId = `fake-${rand()}`;
    const fromHeader = `"${displayName}" <sip:${from}@${this.realm}>;tag=${rand(4)}`;
    const toHeader = `<sip:${username}@${this.realm}>`;
    const call = {
      callId, direction: 'outbound', ws: reg.ws, uri: reg.contactUri, fromHeader, toHeader,
      cseq: ++this._cseq, state: 'inviting', remoteContact: reg.contactUri
    };
    this.calls.set(callId, call);
    this._send(reg.ws, this._request('INVITE', reg.contactUri, {
      headers: [
        `From: ${fromHeader}`,
        `To: ${toHeader}`,
        `Call-ID: ${callId}`,
        `CSeq: ${call.cseq} INVITE`,
        `Contact: <sip:fake@${this.realm};transport=ws>`,
        'Content-Type: application/sdp'
      ],
      body: sdp
    }));
    return callId;
  }

  isRegistered(username) {
    return this.registrations.has(username);
  }
}

function defaultAnswerSdp() {
  const fp = Array.from(crypto.randomBytes(32), (b) => b.toString(16).padStart(2, '0').toUpperCase()).join(':');
  return [
    'v=0',
    'o=- 1 1 IN IP4 127.0.0.1',
    's=Asterisk',
    'c=IN IP4 127.0.0.1',
    't=0 0',
    'a=group:BUNDLE 0',
    'm=audio 10000 UDP/TLS/RTP/SAVPF 111 0 126',
    'a=mid:0',
    'a=ice-ufrag:fakeufrag',
    'a=ice-pwd:fakepwdfakepwdfakepwd',
    'a=candidate:Hac120003 1 UDP 2130706431 127.0.0.1 10000 typ host',
    `a=fingerprint:sha-256 ${fp}`,
    'a=setup:active',
    'a=rtcp-mux',
    'a=rtpmap:111 opus/48000/2',
    'a=rtpmap:0 PCMU/8000',
    'a=rtpmap:126 telephone-event/8000',
    'a=sendrecv',
    ''
  ].join('\r\n');
}

module.exports = { FakeSipServer, parseSip, defaultAnswerSdp };
