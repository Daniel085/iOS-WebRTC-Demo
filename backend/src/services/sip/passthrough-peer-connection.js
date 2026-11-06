/**
 * Pass-through RTCPeerConnection for running JsSIP under Node.
 *
 * JsSIP always drives an RTCPeerConnection: it calls createOffer()/
 * createAnswer(), setLocalDescription() and setRemoteDescription() and puts
 * `pc.localDescription.sdp` into the INVITE / 200 OK. The gateway never
 * touches media: the SDP comes from the app and the answer goes back to the
 * app unchanged. This class satisfies JsSIP's expectations with no WebRTC
 * stack at all: the "offer" it creates is whatever SDP was handed to it with
 * setPendingLocalSdp(), and ICE gathering is always reported complete (the
 * app already gathered its candidates, see sdp.js).
 *
 * installNodeWebRtcShims() publishes this class (plus a trivial
 * RTCSessionDescription and `window`) on globalThis, which is where JsSIP
 * looks for them.
 */

class PassthroughPeerConnection extends EventTarget {
  constructor(configuration = {}) {
    super();
    this.configuration = configuration;
    this.localDescription = null;
    this.remoteDescription = null;
    this.signalingState = 'stable';
    this.iceGatheringState = 'complete';
    this.iceConnectionState = 'new';
    this.connectionState = 'new';
    this._pendingLocalSdp = null;
  }

  /** SDP that the next createOffer()/createAnswer() must return. */
  setPendingLocalSdp(sdp) {
    this._pendingLocalSdp = sdp;
  }

  _nextLocalSdp(kind) {
    if (this._pendingLocalSdp) {
      const sdp = this._pendingLocalSdp;
      this._pendingLocalSdp = null;
      return sdp;
    }
    // Re-INVITE / session refresh from the far end: answer with what we
    // already offered. No new SDP is involved, the media stays as negotiated.
    if (this.localDescription && this.localDescription.sdp) {
      return this.localDescription.sdp;
    }
    throw new Error(`PassthroughPeerConnection: no local SDP available for ${kind}`);
  }

  async createOffer() {
    return { type: 'offer', sdp: this._nextLocalSdp('offer') };
  }

  async createAnswer() {
    return { type: 'answer', sdp: this._nextLocalSdp('answer') };
  }

  async setLocalDescription(description) {
    this._assertOpen();
    this.localDescription = { type: description.type, sdp: description.sdp };
    this.signalingState = description.type === 'offer' ? 'have-local-offer' : 'stable';
  }

  async setRemoteDescription(description) {
    this._assertOpen();
    this.remoteDescription = { type: description.type, sdp: description.sdp };
    this.signalingState = description.type === 'offer' ? 'have-remote-offer' : 'stable';
  }

  async addIceCandidate() { /* candidates are embedded in the SDP */ }

  getConfiguration() { return this.configuration; }
  getSenders() { return []; }
  getReceivers() { return []; }
  getTransceivers() { return []; }
  getLocalStreams() { return []; }
  getRemoteStreams() { return []; }
  async getStats() { return new Map(); }

  addTrack() {
    throw new Error('PassthroughPeerConnection carries no media; the gateway only relays SDP');
  }

  removeTrack() {}

  close() {
    this.signalingState = 'closed';
    this.iceConnectionState = 'closed';
    this.connectionState = 'closed';
  }

  _assertOpen() {
    if (this.signalingState === 'closed') {
      throw new Error('PassthroughPeerConnection is closed');
    }
  }
}

class PassthroughSessionDescription {
  constructor({ type, sdp } = {}) {
    this.type = type;
    this.sdp = sdp;
  }

  toJSON() {
    return { type: this.type, sdp: this.sdp };
  }
}

/**
 * Make JsSIP believe it runs in a WebRTC-capable environment. Idempotent and
 * only fills in globals that are missing, so a real implementation (or a
 * browser) is never overridden.
 */
function installNodeWebRtcShims(target = globalThis) {
  if (typeof target.window === 'undefined') {
    // JsSIP reads `window.RTCPeerConnection`; pointing window at the global
    // object keeps other libraries' `typeof window` checks consistent.
    target.window = target;
  }
  if (typeof target.RTCPeerConnection === 'undefined') {
    target.RTCPeerConnection = PassthroughPeerConnection;
  }
  if (typeof target.RTCSessionDescription === 'undefined') {
    target.RTCSessionDescription = PassthroughSessionDescription;
  }
  return target;
}

module.exports = {
  PassthroughPeerConnection,
  PassthroughSessionDescription,
  installNodeWebRtcShims
};
