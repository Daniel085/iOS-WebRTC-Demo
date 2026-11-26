/**
 * Minimal Asterisk Manager Interface (AMI) client: log in, run one CLI
 * command, log off. Used to `pjsip reload` after provisioning an endpoint.
 */

const net = require('net');

function parseAmiPackets(buffer) {
  const packets = [];
  let rest = buffer;
  let idx;
  while ((idx = rest.indexOf('\r\n\r\n')) !== -1) {
    const raw = rest.slice(0, idx);
    rest = rest.slice(idx + 4);
    const packet = { _raw: raw, Output: [] };
    for (const line of raw.split('\r\n')) {
      const sep = line.indexOf(':');
      if (sep === -1) continue;
      const key = line.slice(0, sep).trim();
      const value = line.slice(sep + 1).trim();
      if (key === 'Output') packet.Output.push(value);
      else packet[key] = value;
    }
    packets.push(packet);
  }
  return { packets, rest };
}

/**
 * @param {object} ami   { host, port, username, secret, timeoutMs }
 * @param {string} command  Asterisk CLI command, e.g. "pjsip reload"
 * @returns {Promise<string>} command output
 */
function amiCommand(ami, command) {
  const { host, port = 5038, username, secret, timeoutMs = 5000 } = ami;
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host, port });
    let buffer = '';
    let done = false;

    const finish = (error, result) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      socket.destroy();
      if (error) reject(error);
      else resolve(result);
    };
    const timer = setTimeout(() => finish(new Error(`AMI ${host}:${port} timed out`)), timeoutMs);

    const send = (lines) => socket.write(`${lines.join('\r\n')}\r\n\r\n`);

    socket.on('connect', () => {
      send(['Action: Login', `Username: ${username}`, `Secret: ${secret}`, 'Events: off', 'ActionID: login']);
    });
    socket.on('error', (error) => finish(new Error(`AMI ${host}:${port}: ${error.message}`)));
    socket.on('close', () => finish(new Error('AMI connection closed before the command completed')));
    socket.on('data', (chunk) => {
      buffer += chunk.toString('utf8');
      // The greeting ("Asterisk Call Manager/x.y") is a single line with no blank line after it.
      if (buffer.startsWith('Asterisk Call Manager')) {
        const eol = buffer.indexOf('\r\n');
        if (eol === -1) return;
        buffer = buffer.slice(eol + 2);
      }
      const { packets, rest } = parseAmiPackets(buffer);
      buffer = rest;
      for (const packet of packets) {
        if (packet.ActionID === 'login') {
          if (packet.Response !== 'Success') return finish(new Error(`AMI login failed: ${packet.Message || packet.Response}`));
          send(['Action: Command', `Command: ${command}`, 'ActionID: cmd']);
        } else if (packet.ActionID === 'cmd') {
          if (packet.Response === 'Error') return finish(new Error(`AMI command failed: ${packet.Message || 'error'}`));
          // Asterisk >= 14 returns "Output:" lines; older versions used "Response: Follows" + raw text.
          const output = packet.Output.length
            ? packet.Output
            : packet._raw.split('\r\n').filter((l) => !/^(Response|ActionID|Privilege|Message):/.test(l));
          send(['Action: Logoff']);
          finish(null, output.join('\n'));
        }
      }
    });
  });
}

module.exports = { amiCommand, parseAmiPackets };
