/**
 * JsSIP Socket implementation on top of the `ws` package.
 *
 * JsSIP ships WebSocketInterface, which expects the browser WebSocket API.
 * Node's built-in WebSocket cannot be told to accept a self-signed
 * certificate, so the gateway uses `ws` directly and implements the small
 * interface documented at https://jssip.net/documentation/3.x/api/socket/
 */

const WebSocket = require('ws');

class NodeWebSocketInterface {
  /**
   * @param {string} url                      ws:// or wss:// URL of Asterisk (…/ws)
   * @param {object} [options]
   * @param {boolean} [options.rejectUnauthorized=true]  false accepts self-signed TLS certs
   * @param {number}  [options.handshakeTimeout=10000]
   * @param {Function} [options.WebSocketImpl]  injectable for tests
   */
  constructor(url, options = {}) {
    const parsed = new URL(url);
    if (parsed.protocol !== 'ws:' && parsed.protocol !== 'wss:') {
      throw new TypeError(`Invalid SIP WebSocket URL: ${url}`);
    }
    this._url = url;
    this._options = options;
    this._WebSocket = options.WebSocketImpl || WebSocket;
    this._ws = null;
    this._via_transport = parsed.protocol === 'wss:' ? 'WSS' : 'WS';
    const port = parsed.port ? `:${parsed.port}` : '';
    this._sip_uri = `sip:${parsed.hostname}${port};transport=ws`;

    // Assigned by JsSIP's Transport.
    this.onconnect = () => {};
    this.ondisconnect = () => {};
    this.ondata = () => {};
  }

  get via_transport() { return this._via_transport; }
  set via_transport(value) { this._via_transport = String(value).toUpperCase(); }
  get sip_uri() { return this._sip_uri; }
  get url() { return this._url; }

  connect() {
    if (this.isConnected() || this.isConnecting()) return;
    if (this._ws) this.disconnect();

    const ws = new this._WebSocket(this._url, ['sip'], {
      rejectUnauthorized: this._options.rejectUnauthorized !== false,
      handshakeTimeout: this._options.handshakeTimeout || 10000
    });
    this._ws = ws;

    ws.on('open', () => this.onconnect());
    ws.on('message', (data) => this.ondata(typeof data === 'string' ? data : data.toString('utf8')));
    ws.on('close', (code, reason) => {
      const clean = code === 1000;
      this.ondisconnect(!clean, code, reason ? reason.toString() : '');
    });
    ws.on('error', (error) => {
      // 'close' follows an error; JsSIP's recovery logic takes over there.
      this._lastError = error;
    });
  }

  disconnect() {
    if (!this._ws) return;
    const ws = this._ws;
    this._ws = null;
    ws.removeAllListeners();
    ws.on('error', () => {});
    try { ws.close(1000); } catch (_) { /* already closed */ }
  }

  send(message) {
    if (!this.isConnected()) return false;
    this._ws.send(message);
    return true;
  }

  isConnected() {
    return !!this._ws && this._ws.readyState === this._WebSocket.OPEN;
  }

  isConnecting() {
    return !!this._ws && this._ws.readyState === this._WebSocket.CONNECTING;
  }

  get lastError() { return this._lastError || null; }
}

module.exports = { NodeWebSocketInterface };
