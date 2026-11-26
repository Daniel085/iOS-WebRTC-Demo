/**
 * Synthetic WebRTC-style SDP for tests and the integration script.
 * Shaped like what libwebrtc produces for an audio-only call: ICE
 * credentials, DTLS fingerprint, BUNDLE, rtcp-mux, Opus + G.711 + DTMF.
 * There is no media stack behind it, so Asterisk will answer (200 OK with its
 * own fingerprint) and later time out the DTLS handshake. That is enough to
 * verify the signaling path end to end.
 */
const crypto = require('crypto');
const os = require('os');

function lanIp() {
  for (const ifaces of Object.values(os.networkInterfaces())) {
    for (const iface of ifaces || []) {
      if (iface.family === 'IPv4' && !iface.internal) return iface.address;
    }
  }
  return '127.0.0.1';
}

const token = (bytes) => crypto.randomBytes(bytes).toString('base64url').slice(0, bytes);

function fingerprint() {
  return Array.from(crypto.randomBytes(32), (b) => b.toString(16).padStart(2, '0').toUpperCase()).join(':');
}

function makeCandidate(ip = lanIp(), port = 40000 + Math.floor(Math.random() * 20000)) {
  return {
    candidate: `candidate:${Math.floor(Math.random() * 1e9)} 1 udp 2130706431 ${ip} ${port} typ host generation 0`,
    sdpMid: '0',
    sdpMLineIndex: 0
  };
}

/**
 * @param {object} [options]
 * @param {boolean} [options.withCandidates=false]  embed a host candidate + end-of-candidates (complete SDP)
 * @param {string}  [options.ip]
 * @param {'offer'|'answer'} [options.type='offer']  answers use a=setup:active
 */
function makeSdp({ withCandidates = false, ip = lanIp(), type = 'offer' } = {}) {
  const lines = [
    'v=0',
    `o=- ${Date.now()} 2 IN IP4 127.0.0.1`,
    's=-',
    't=0 0',
    'a=group:BUNDLE 0',
    'a=msid-semantic: WMS stream0',
    'm=audio 9 UDP/TLS/RTP/SAVPF 111 0 8 126',
    'c=IN IP4 0.0.0.0',
    'a=rtcp:9 IN IP4 0.0.0.0',
    `a=ice-ufrag:${token(8)}`,
    `a=ice-pwd:${token(24)}`,
    `a=fingerprint:sha-256 ${fingerprint()}`,
    `a=setup:${type === 'answer' ? 'active' : 'actpass'}`,
    'a=mid:0',
    'a=sendrecv',
    'a=rtcp-mux',
    'a=rtpmap:111 opus/48000/2',
    'a=fmtp:111 minptime=10;useinbandfec=1',
    'a=rtpmap:0 PCMU/8000',
    'a=rtpmap:8 PCMA/8000',
    'a=rtpmap:126 telephone-event/8000',
    'a=fmtp:126 0-16',
    `a=ssrc:${Math.floor(Math.random() * 1e9)} cname:${token(16)}`
  ];
  if (withCandidates) {
    lines.push(`a=${makeCandidate(ip).candidate}`);
    lines.push('a=end-of-candidates');
  }
  return `${lines.join('\r\n')}\r\n`;
}

const makeOffer = (options = {}) => makeSdp({ ...options, type: 'offer' });
const makeAnswer = (options = {}) => makeSdp({ ...options, type: 'answer' });

module.exports = { makeSdp, makeOffer, makeAnswer, makeCandidate, lanIp, fingerprint };
