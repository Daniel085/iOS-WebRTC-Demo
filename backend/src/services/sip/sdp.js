/**
 * SDP helpers for the SIP gateway.
 *
 * The app trickles ICE candidates over Socket.IO (`ice-candidate` events), but
 * SIP toward Asterisk needs ONE complete SDP in the INVITE / 200 OK (no trickle
 * ICE, see docs/SIP_INTEGRATION.md "ICE: use full gathering"). These helpers
 * fold the buffered candidates back into the SDP and decide which dialled
 * strings are SIP destinations at all.
 */

const E164 = /^\+[1-9]\d{1,14}$/;
const SIP_URI = /^sips?:[^\s@]+(@[^\s]+)?$/i;
// Asterisk dialplan feature codes such as *43 (echo test) or *44 (playback test).
const FEATURE_CODE = /^\*\d{1,6}$/;

function isE164(value) {
  return typeof value === 'string' && E164.test(value);
}

function isSipUri(value) {
  return typeof value === 'string' && SIP_URI.test(value);
}

function isFeatureCode(value) {
  return typeof value === 'string' && FEATURE_CODE.test(value);
}

/**
 * Routing rule from docs/SIP_INTEGRATION.md: anything that is an E.164
 * number, a sip:/sips: URI or an Asterisk feature code can be handed to the
 * gateway. Everything else is an error for the caller.
 */
function isSipDestination(value) {
  return isE164(value) || isSipUri(value) || isFeatureCode(value);
}

/**
 * Build the SIP request URI for a destination: URIs pass through, numbers and
 * feature codes are addressed at the Asterisk domain.
 */
function sipTargetFor(destination, domain) {
  if (isSipUri(destination)) return destination;
  return `sip:${destination}@${domain}`;
}

/**
 * Normalise the many shapes an ICE candidate can arrive in:
 *   - a string ("candidate:1 1 udp ... typ host" or "a=candidate:...")
 *   - { candidate, sdpMid, sdpMLineIndex }   (W3C RTCIceCandidateInit, what the iOS app sends)
 *   - { sdp, sdpMid, sdpMLineIndex }          (older RTCIceCandidate shape)
 * Returns null for an end-of-candidates marker (null / '' / { candidate: '' }).
 */
function normalizeCandidate(input) {
  if (input === null || input === undefined) return null;
  let raw;
  let sdpMid = null;
  let sdpMLineIndex = null;

  if (typeof input === 'string') {
    raw = input;
  } else if (typeof input === 'object') {
    if (input.endOfCandidates === true) return null;
    raw = input.candidate !== undefined ? input.candidate : input.sdp;
    if (typeof input.sdpMid === 'string' && input.sdpMid !== '') sdpMid = input.sdpMid;
    if (Number.isInteger(input.sdpMLineIndex)) sdpMLineIndex = input.sdpMLineIndex;
    else if (typeof input.sdpMLineIndex === 'string' && /^\d+$/.test(input.sdpMLineIndex)) {
      sdpMLineIndex = parseInt(input.sdpMLineIndex, 10);
    }
  } else {
    return null;
  }

  if (typeof raw !== 'string') return null;
  raw = raw.trim();
  if (raw === '') return null;
  if (raw.startsWith('a=')) raw = raw.slice(2);
  if (!raw.startsWith('candidate:')) raw = `candidate:${raw}`;

  return { line: `a=${raw}`, sdpMid, sdpMLineIndex };
}

function isEndOfCandidates(input) {
  return normalizeCandidate(input) === null;
}

function hasEndOfCandidates(sdp) {
  return typeof sdp === 'string' && /^a=end-of-candidates\s*$/m.test(sdp);
}

function hasCandidates(sdp) {
  return typeof sdp === 'string' && /^a=candidate:/m.test(sdp);
}

/**
 * Split an SDP into its session section and media sections (each starting
 * with an m= line). Lines keep no trailing CR/LF.
 */
function splitSdp(sdp) {
  const lines = String(sdp).split(/\r?\n/).filter((line, i, arr) => !(line === '' && i === arr.length - 1));
  const session = [];
  const media = [];
  let current = session;
  for (const line of lines) {
    if (line.startsWith('m=')) {
      current = [];
      media.push(current);
    }
    current.push(line);
  }
  return { session, media };
}

function joinSdp({ session, media }) {
  const all = [...session];
  for (const section of media) all.push(...section);
  return `${all.join('\r\n')}\r\n`;
}

function midOf(section) {
  const midLine = section.find((line) => line.startsWith('a=mid:'));
  return midLine ? midLine.slice('a=mid:'.length).trim() : null;
}

/**
 * Fold ICE candidates into an SDP and mark every media section with
 * a=end-of-candidates, producing the complete offer/answer SIP needs.
 *
 * @param {string} sdp            base SDP from the app (may already contain candidates)
 * @param {Array} candidates      candidates in any of the shapes normalizeCandidate accepts
 * @returns {string}              CRLF-terminated SDP
 */
function assembleSdp(sdp, candidates = []) {
  const parts = splitSdp(sdp);
  if (parts.media.length === 0) {
    throw new Error('assembleSdp: SDP has no media section');
  }

  for (const input of candidates) {
    const cand = normalizeCandidate(input);
    if (!cand) continue;

    let index = 0;
    if (cand.sdpMLineIndex !== null && cand.sdpMLineIndex >= 0 && cand.sdpMLineIndex < parts.media.length) {
      index = cand.sdpMLineIndex;
    } else if (cand.sdpMid !== null) {
      const byMid = parts.media.findIndex((section) => midOf(section) === cand.sdpMid);
      if (byMid >= 0) index = byMid;
    }

    const section = parts.media[index];
    if (section.includes(cand.line)) continue; // already present

    // Keep candidates together and before any end-of-candidates marker.
    const eoc = section.indexOf('a=end-of-candidates');
    if (eoc >= 0) section.splice(eoc, 0, cand.line);
    else section.push(cand.line);
  }

  for (const section of parts.media) {
    if (!section.includes('a=end-of-candidates')) section.push('a=end-of-candidates');
  }

  return joinSdp(parts);
}

/**
 * Extract the user part of a SIP From/To URI as a dialable string:
 * "15550000001" -> "+15550000001", "webrtc_test" stays as is.
 */
function dialableFromSipUser(user) {
  if (!user) return 'unknown';
  if (/^\+?\d{3,15}$/.test(user)) return user.startsWith('+') ? user : `+${user}`;
  return user;
}

module.exports = {
  isE164,
  isSipUri,
  isFeatureCode,
  isSipDestination,
  sipTargetFor,
  normalizeCandidate,
  isEndOfCandidates,
  hasEndOfCandidates,
  hasCandidates,
  assembleSdp,
  splitSdp,
  dialableFromSipUser
};
