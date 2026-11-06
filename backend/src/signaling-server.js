/**
 * Signaling Server
 * Handles WebSocket connections for real-time call signaling
 */

const http = require('http');
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');

const logger = require('./utils/logger');
const { sendVoIPPush } = require('./services/voip-push');
const db = require('./database/models');
const { getGateway, SIP_EVENTS } = require('./services/sip-gateway');

// Store active connections: Map<userId, {socketId, phoneNumber}>
const connectedUsers = new Map();

// Store active calls: Map<callId, {caller, callee, status}>
const activeCalls = new Map();

// Call IDs are stored in a UUID column; anything else would make every
// database write for the call fail, so it is rejected before the call exists.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isValidCallId = (callId) => typeof callId === 'string' && UUID_PATTERN.test(callId);

// Database writes for one call run strictly in the order they were requested.
// Each handler awaits its own write, but handlers for the same call overlap:
// an answer, reject or hang-up that arrives within a few milliseconds of
// call-initiate would otherwise send its UPDATE on another pooled connection
// before the INSERT has committed, match no row, and leave the call recorded
// as "initiated" forever. The returned promise still rejects with that write's
// own error; a failed write does not block the ones queued behind it.
const callRecordWrites = new Map(); // callId -> tail of that call's write chain

function writeCallRecord(callId, write) {
  const previous = callRecordWrites.get(callId) || Promise.resolve();
  const result = previous.then(write);
  const tail = result.catch(() => {});
  callRecordWrites.set(callId, tail);
  tail.then(() => {
    if (callRecordWrites.get(callId) === tail) {
      callRecordWrites.delete(callId);
    }
  });
  return result;
}

// Calls where both people agreed to transcription. Kept for a day after the
// call so either participant can ask for a summary (POST /api/calls/:id/summary).
// Only participants and phone numbers are kept, never transcript text.
// Map<callId, {participants: [userId, userId], phones: {userId: phone}, expiresAt}>
const transcribedCalls = new Map();
const TRANSCRIBED_CALL_TTL_MS = 24 * 60 * 60 * 1000;

function rememberTranscribedCall(callId, call) {
  transcribedCalls.set(callId, {
    participants: [call.callerId, call.calleeId],
    phones: { [call.callerId]: call.callerPhone, [call.calleeId]: call.calleePhone },
    expiresAt: Date.now() + TRANSCRIBED_CALL_TTL_MS
  });
}

function getTranscribedCall(callId) {
  const record = transcribedCalls.get(callId);
  if (!record) return null;
  if (record.expiresAt < Date.now()) {
    transcribedCalls.delete(callId);
    return null;
  }
  return record;
}

const transcribedCallSweep = setInterval(() => {
  const now = Date.now();
  transcribedCalls.forEach((record, callId) => {
    if (record.expiresAt < now) transcribedCalls.delete(callId);
  });
}, 60 * 60 * 1000);
transcribedCallSweep.unref();

const MAX_SEGMENT_TEXT = 2000;

/**
 * Create the Socket.IO signaling layer.
 *
 * @param {http.Server} [existingServer] - When provided (the default in
 *   src/index.js), signaling is attached to the same HTTP server as the REST
 *   API so everything runs on ONE port. This keeps the backend deployable on
 *   platforms that expose a single port (Fly.io, Render, Railway, Heroku...).
 *   When omitted, a standalone HTTP server is created (used by `npm run dev:signaling`).
 * @param {object} [options]
 * @param {SipGateway} [options.sipGateway] - SIP gateway for non-app destinations
 *   (defaults to the process-wide one built from SIP_* env vars; tests inject their own).
 */
function createSignalingServer(existingServer, { sipGateway = getGateway() } = {}) {
  const server = existingServer || http.createServer();

  const io = new Server(server, {
    cors: {
      origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
      credentials: true
    },
    pingTimeout: 60000,
    pingInterval: 25000
  });

  // ---- SIP gateway plumbing -------------------------------------------------

  // Deliver an event to a user if connected, otherwise park it on the call so
  // the register handler replays it (same mechanism as VoIP-push wake-ups).
  const deliverToUser = (userId, event, payload, call) => {
    const connection = connectedUsers.get(userId);
    if (connection) {
      io.to(connection.socketId).emit(event, payload);
      return true;
    }
    if (call) {
      call.pendingSignals = call.pendingSignals || [];
      call.pendingSignals.push({ toUserId: userId, event, payload });
    }
    return false;
  };

  // Forward everything a SIP call session emits (call-ringing, answer,
  // call-answered, call-ended, call-error) to the app user it belongs to and
  // drop the call when the SIP leg closes for any reason.
  const attachSipSession = (callId, call, session, userId) => {
    for (const event of SIP_EVENTS) {
      session.on(event, (payload) => deliverToUser(userId, event, payload, call));
    }
    session.on('closed', async ({ status }) => {
      if (activeCalls.get(callId) === call) activeCalls.delete(callId);
      logger.info(`SIP call ${callId} closed (${status})`);
      try {
        await db.Call.update(
          { status: status === 'answered' ? 'ended' : status, endedAt: new Date() },
          { where: { id: callId } }
        );
      } catch (error) {
        logger.debug(`Call ${callId}: database update after SIP close failed: ${error.message}`);
      }
    });
  };

  // Inbound SIP call (Asterisk -> this user's gateway UA) -> app incoming-call + offer.
  if (sipGateway.enabled) {
    sipGateway.on('incoming-call', async (session) => {
      const { callId, user, from, remoteSdp } = session;
      const call = {
        callerId: null,
        callerPhone: from,
        calleeId: user.id,
        calleePhone: user.phoneNumber,
        hasVideo: false,
        via: 'sip',
        direction: 'incoming',
        status: 'ringing',
        sipSession: session,
        createdAt: new Date()
      };
      activeCalls.set(callId, call);
      attachSipSession(callId, call, session, user.id);

      const timestamp = new Date().toISOString();
      const online = deliverToUser(user.id, 'incoming-call', { callId, from, hasVideo: false, via: 'sip', timestamp }, call);
      deliverToUser(user.id, 'offer', { callId, sdp: remoteSdp, from, hasVideo: false }, call);
      logger.info(`Inbound SIP call ${callId}: ${from} -> ${user.phoneNumber} (${online ? 'online' : 'offline'})`);

      if (!online) {
        try {
          const voipToken = await db.VoipToken.findOne({
            where: { userId: user.id },
            order: [['createdAt', 'DESC']]
          });
          if (voipToken) {
            await sendVoIPPush(voipToken.token, { callId, caller: from, hasVideo: false });
            logger.info(`VoIP push sent for inbound SIP call ${callId}`);
          } else {
            logger.warn(`Inbound SIP call ${callId}: ${user.phoneNumber} offline and no VoIP token; rejecting`);
            session.terminate({ statusCode: 480, reason: 'Temporarily Unavailable' });
          }
        } catch (error) {
          logger.error(`Inbound SIP call ${callId}: VoIP push failed: ${error.message}`);
          session.terminate({ statusCode: 480, reason: 'Temporarily Unavailable' });
        }
      }
    });
  }

  // Authentication middleware
  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth.token || socket.handshake.headers.authorization?.replace('Bearer ', '');

      if (!token) {
        return next(new Error('Authentication error: No token provided'));
      }

      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      socket.userId = decoded.userId;
      socket.phoneNumber = decoded.phoneNumber;

      logger.debug(`User authenticated: ${socket.phoneNumber}`);
      next();
    } catch (error) {
      logger.error('Authentication error:', error.message);
      next(new Error('Authentication error: Invalid token'));
    }
  });

  io.on('connection', (socket) => {
    logger.info(`Client connected: ${socket.phoneNumber} (${socket.id})`);

    /**
     * Route a call to the SIP gateway (E.164 number, sip: URI or Asterisk
     * feature code that is not an app user). The INVITE goes out once the
     * app's offer and ICE candidates have arrived.
     */
    const startSipCall = ({ to, callId, hasVideo }) => {
      if (activeCalls.has(callId)) {
        socket.emit('call-error', { callId, error: 'Call ID already in use' });
        return;
      }
      let session;
      try {
        session = sipGateway.placeCall({ id: socket.userId, phoneNumber: socket.phoneNumber }, to, { callId, hasVideo });
      } catch (error) {
        logger.error(`SIP call ${callId}: ${error.message}`);
        socket.emit('call-error', { callId, error: 'Failed to initiate SIP call' });
        return;
      }
      const call = {
        callerId: socket.userId,
        callerPhone: socket.phoneNumber,
        calleeId: null,
        calleePhone: to,
        hasVideo,
        via: 'sip',
        direction: 'outgoing',
        status: 'initiating',
        sipSession: session,
        createdAt: new Date()
      };
      activeCalls.set(callId, call);
      attachSipSession(callId, call, session, socket.userId);
      // Call records for SIP legs (no callee user id) arrive with Phase 5.
      logger.info(`Call ${callId} routed to SIP gateway: ${socket.phoneNumber} -> ${to}`);
    };

    // Register user connection
    socket.on('register', () => {
      connectedUsers.set(socket.userId, {
        socketId: socket.id,
        phoneNumber: socket.phoneNumber,
        connectedAt: new Date()
      });
      logger.info(`User registered: ${socket.phoneNumber}`);

      socket.emit('registered', { success: true, phoneNumber: socket.phoneNumber });

      // Keep a SIP registration alive for this user while the app is connected
      // so Asterisk can route inbound calls to it (docs/SIP_INTEGRATION.md,
      // "Registration and presence", option 1).
      if (sipGateway.enabled) {
        sipGateway.ensureUserAgent({ id: socket.userId, phoneNumber: socket.phoneNumber })
          .catch((error) => logger.warn(`SIP registration for ${socket.phoneNumber} failed: ${error.message}`));
      }

      // Deliver any offer / ICE candidates that arrived while this user was
      // offline (e.g. the callee was woken by a VoIP push after the caller had
      // already sent its SDP offer).
      activeCalls.forEach((call, callId) => {
        const pending = call.pendingSignals;
        if (!pending || pending.length === 0) return;
        const mine = pending.filter((signal) => signal.toUserId === socket.userId);
        if (mine.length === 0) return;
        mine.forEach((signal) => socket.emit(signal.event, signal.payload));
        call.pendingSignals = pending.filter((signal) => signal.toUserId !== socket.userId);
        logger.info(`Delivered ${mine.length} buffered signaling message(s) for call ${callId} to ${socket.phoneNumber}`);
      });
    });

    // Initiate a call
    socket.on('call-initiate', async (data) => {
      try {
        const { to, callId, hasVideo } = data;

        if (!isValidCallId(callId)) {
          socket.emit('call-error', { callId, error: 'Invalid call ID (must be a UUID)' });
          return;
        }

        logger.info(`Call initiated: ${socket.phoneNumber} -> ${to} (${callId})`);

        // Find recipient
        const recipient = await db.User.findOne({ where: { phoneNumber: to } });

        if (!recipient) {
          // Not an app user: hand E.164 numbers, sip: URIs and Asterisk
          // feature codes to the SIP gateway when it is enabled.
          if (sipGateway.enabled && sipGateway.isSipDestination(to)) {
            startSipCall({ to, callId, hasVideo });
          } else {
            socket.emit('call-error', { callId, error: sipGateway.enabled ? 'Unknown destination' : 'User not found' });
          }
          return;
        }

        // Store call information
        activeCalls.set(callId, {
          callerId: socket.userId,
          callerPhone: socket.phoneNumber,
          calleeId: recipient.id,
          calleePhone: to,
          hasVideo,
          status: 'initiating',
          createdAt: new Date()
        });

        // Check if recipient is online
        const recipientConnection = connectedUsers.get(recipient.id);

        if (recipientConnection) {
          // Send call notification via WebSocket
          io.to(recipientConnection.socketId).emit('incoming-call', {
            callId,
            from: socket.phoneNumber,
            hasVideo,
            timestamp: new Date().toISOString()
          });
          logger.info(`Call notification sent via WebSocket to ${to}`);
        } else {
          // User offline - send VoIP push notification to the most recently
          // registered token that has not been unregistered (DELETE /api/user/voip-token
          // only deactivates rows, it does not delete them).
          const voipToken = await db.VoipToken.findOne({
            where: { userId: recipient.id, isActive: true },
            order: [['createdAt', 'DESC']]
          });

          if (voipToken) {
            await sendVoIPPush(voipToken.token, {
              callId,
              caller: socket.phoneNumber,
              hasVideo
            });
            logger.info(`VoIP push sent to ${to}`);
          } else {
            socket.emit('call-error', { callId, error: 'Recipient unavailable' });
            activeCalls.delete(callId);
          }
        }

        // Save call to database
        await writeCallRecord(callId, () => db.Call.create({
          id: callId,
          callerId: socket.userId,
          calleeId: recipient.id,
          type: hasVideo ? 'video' : 'audio',
          status: 'initiated',
          startedAt: new Date()
        }));

      } catch (error) {
        logger.error('Error initiating call:', error);
        socket.emit('call-error', { error: 'Failed to initiate call' });
      }
    });

    // Answer a call
    socket.on('call-answer', async (data) => {
      try {
        const { callId } = data;
        const call = activeCalls.get(callId);

        if (!call) {
          socket.emit('call-error', { callId, error: 'Call not found' });
          return;
        }

        if (call.via === 'sip') {
          // Inbound SIP call: the 200 OK goes out once the app's answer SDP
          // (plus ICE candidates) has arrived, see the 'answer' handler.
          call.status = 'answered';
          return;
        }

        call.status = 'answered';
        activeCalls.set(callId, call);

        // Notify caller that call was answered
        const callerConnection = connectedUsers.get(call.callerId);
        if (callerConnection) {
          io.to(callerConnection.socketId).emit('call-answered', {
            callId,
            by: socket.phoneNumber
          });
        }

        // Update call in database
        await writeCallRecord(callId, () => db.Call.update(
          { status: 'answered', answeredAt: new Date() },
          { where: { id: callId } }
        ));

        logger.info(`Call answered: ${callId}`);
      } catch (error) {
        logger.error('Error answering call:', error);
        socket.emit('call-error', { callId: data.callId, error: 'Failed to answer call' });
      }
    });

    // Reject a call
    socket.on('call-reject', async (data) => {
      try {
        const { callId, reason } = data;
        const call = activeCalls.get(callId);

        if (!call) {
          return;
        }

        if (call.via === 'sip') {
          const busy = reason === 'busy';
          call.sipSession.terminate({ statusCode: busy ? 486 : 603, reason: busy ? 'Busy Here' : 'Decline' });
          activeCalls.delete(callId);
          logger.info(`SIP call rejected: ${callId}`);
          return;
        }

        // Notify caller
        const callerConnection = connectedUsers.get(call.callerId);
        if (callerConnection) {
          io.to(callerConnection.socketId).emit('call-rejected', {
            callId,
            by: socket.phoneNumber,
            reason: reason || 'declined'
          });
        }

        // Forget the call before writing, as call-end does, so a failed write
        // cannot leave it registered.
        activeCalls.delete(callId);
        logger.info(`Call rejected: ${callId}`);

        // Update database
        await writeCallRecord(callId, () => db.Call.update(
          { status: 'rejected', endedAt: new Date() },
          { where: { id: callId } }
        ));
      } catch (error) {
        logger.error('Error rejecting call:', error);
      }
    });

    // End a call
    socket.on('call-end', async (data) => {
      try {
        const { callId } = data;
        const call = activeCalls.get(callId);

        if (!call) {
          return;
        }

        if (call.via === 'sip') {
          call.sipSession.terminate(); // CANCEL before answer, BYE after; 'closed' cleans up
          activeCalls.delete(callId);
          logger.info(`SIP call ended by app: ${callId}`);
          return;
        }

        // Notify the other party
        const otherUserId = call.callerId === socket.userId ? call.calleeId : call.callerId;
        const otherConnection = connectedUsers.get(otherUserId);

        if (otherConnection) {
          io.to(otherConnection.socketId).emit('call-ended', {
            callId,
            by: socket.phoneNumber
          });
        }

        activeCalls.delete(callId);
        logger.info(`Call ended: ${callId}`);

        // Update database
        await writeCallRecord(callId, () => db.Call.update(
          { status: 'ended', endedAt: new Date() },
          { where: { id: callId } }
        ));
      } catch (error) {
        logger.error('Error ending call:', error);
      }
    });

    /**
     * Resolve the socket of the OTHER participant of a call, based on who is
     * sending. Using the sender's identity (rather than a client-supplied `to`)
     * means a client can never make the server echo signaling back to itself
     * or route it to a third party.
     */
    const otherPartyConnection = (call) => {
      const otherUserId = call.callerId === socket.userId ? call.calleeId : call.callerId;
      return connectedUsers.get(otherUserId);
    };

    // Hold a signaling message for the other party until it registers.
    const bufferForOtherParty = (call, event, payload) => {
      const toUserId = call.callerId === socket.userId ? call.calleeId : call.callerId;
      call.pendingSignals = call.pendingSignals || [];
      call.pendingSignals.push({ toUserId, event, payload });
      logger.debug(`Buffered ${event} for offline party on call ${payload.callId}`);
    };

    // WebRTC Signaling - ICE Candidates
    socket.on('ice-candidate', (data) => {
      const { callId, candidate } = data;
      const call = activeCalls.get(callId);

      if (!call) {
        return;
      }

      if (call.via === 'sip') {
        // Buffered by the gateway; null/empty = end of candidates -> INVITE / 200 OK goes out.
        call.sipSession.addIceCandidate(candidate);
        return;
      }

      // Forward ICE candidate to the other peer
      const recipientConnection = otherPartyConnection(call);

      const payload = { callId, candidate, from: socket.phoneNumber };
      if (recipientConnection) {
        io.to(recipientConnection.socketId).emit('ice-candidate', payload);
        logger.debug(`ICE candidate forwarded for call ${callId}`);
      } else {
        bufferForOtherParty(call, 'ice-candidate', payload);
      }
    });

    // WebRTC Signaling - SDP Offer
    // Normally caller -> callee, but renegotiation (e.g. adding video mid-call)
    // can originate from either side, so always route to the other party.
    socket.on('offer', (data) => {
      const { callId, sdp } = data;
      const call = activeCalls.get(callId);

      if (!call) {
        socket.emit('call-error', { callId, error: 'Call not found' });
        return;
      }

      if (call.via === 'sip') {
        call.sipSession.setOffer(sdp);
        return;
      }

      const recipientConnection = otherPartyConnection(call);
      const payload = { callId, sdp, from: socket.phoneNumber, hasVideo: call.hasVideo };
      if (recipientConnection) {
        io.to(recipientConnection.socketId).emit('offer', payload);
        logger.debug(`SDP offer forwarded for call ${callId}`);
      } else {
        bufferForOtherParty(call, 'offer', payload);
      }
    });

    // WebRTC Signaling - SDP Answer
    socket.on('answer', (data) => {
      const { callId, sdp } = data;
      const call = activeCalls.get(callId);

      if (!call) {
        return;
      }

      if (call.via === 'sip') {
        call.sipSession.setAnswer(sdp);
        return;
      }

      // Forward answer to whoever sent the offer (the other party)
      const callerConnection = otherPartyConnection(call);
      if (callerConnection) {
        io.to(callerConnection.socketId).emit('answer', {
          callId,
          sdp,
          from: socket.phoneNumber
        });
        logger.debug(`SDP answer forwarded for call ${callId}`);
      }
    });

    // ---------------------------------------------------------------
    // Call transcription (consent + caption relay)
    //
    // Either participant may request; only the other may accept. Captions are
    // relayed only while the call's transcription state is 'active', so the
    // server enforces consent. Each change is sent to both participants as
    // `transcription-state {callId, state, byYou}`.
    // ---------------------------------------------------------------

    const callForParticipant = (callId) => {
      const call = activeCalls.get(callId);
      if (!call) return null;
      if (call.callerId !== socket.userId && call.calleeId !== socket.userId) return null;
      return call;
    };

    const emitTranscriptionState = (callId, call, state, actorId) => {
      [call.callerId, call.calleeId].forEach((userId) => {
        const connection = connectedUsers.get(userId);
        if (connection) {
          io.to(connection.socketId).emit('transcription-state', {
            callId,
            state,
            byYou: userId === actorId
          });
        }
      });
    };

    socket.on('transcription-request', (data = {}) => {
      const { callId } = data;
      const call = callForParticipant(callId);
      if (!call) return;
      if (call.status !== 'answered') {
        socket.emit('transcription-state', { callId, state: 'stopped', byYou: true });
        return;
      }
      if (call.transcription?.state === 'active') {
        socket.emit('transcription-state', { callId, state: 'active', byYou: false });
        return;
      }
      call.transcription = { state: 'requested', requestedBy: socket.userId };
      emitTranscriptionState(callId, call, 'requested', socket.userId);
      logger.info(`Transcription requested on call ${callId} by ${socket.phoneNumber}`);
    });

    socket.on('transcription-respond', (data = {}) => {
      const { callId, accepted } = data;
      const call = callForParticipant(callId);
      const transcription = call?.transcription;
      if (!transcription || transcription.state !== 'requested' || transcription.requestedBy === socket.userId) return;

      if (accepted === true) {
        transcription.state = 'active';
        rememberTranscribedCall(callId, call);
        emitTranscriptionState(callId, call, 'active', socket.userId);
        logger.info(`Transcription active on call ${callId}`);
      } else {
        call.transcription = null;
        emitTranscriptionState(callId, call, 'declined', socket.userId);
        logger.info(`Transcription declined on call ${callId}`);
      }
    });

    socket.on('transcription-stop', (data = {}) => {
      const { callId } = data;
      const call = callForParticipant(callId);
      if (!call || !call.transcription) return;
      call.transcription = null;
      emitTranscriptionState(callId, call, 'stopped', socket.userId);
      logger.info(`Transcription stopped on call ${callId} by ${socket.phoneNumber}`);
    });

    socket.on('transcript-segment', (data = {}) => {
      const { callId, segment } = data;
      const call = callForParticipant(callId);
      if (!call || call.transcription?.state !== 'active') return;
      if (!segment || typeof segment.id !== 'string' || typeof segment.text !== 'string') return;

      const recipientConnection = otherPartyConnection(call);
      if (!recipientConnection) return;
      io.to(recipientConnection.socketId).emit('transcript-segment', {
        callId,
        from: socket.phoneNumber,
        segment: {
          id: segment.id.slice(0, 64),
          text: segment.text.slice(0, MAX_SEGMENT_TEXT),
          isFinal: segment.isFinal === true,
          startedAt: Number.isFinite(segment.startedAt) ? segment.startedAt : Date.now()
        }
      });
    });

    // Handle disconnection
    socket.on('disconnect', (reason) => {
      logger.info(`Client disconnected: ${socket.phoneNumber} (${reason})`);

      // Remove from connected users, unless this user already re-registered
      // from a newer socket (reconnect race): then the newer socket owns the
      // registration and the SIP user agent.
      const current = connectedUsers.get(socket.userId);
      const superseded = !!current && current.socketId !== socket.id;
      if (!superseded) {
        connectedUsers.delete(socket.userId);
        if (sipGateway.enabled) sipGateway.releaseUser(socket.userId);
      }

      // End any active calls for this user
      activeCalls.forEach((call, callId) => {
        if (call.callerId === socket.userId || call.calleeId === socket.userId) {
          if (call.via === 'sip') {
            if (!superseded) {
              call.sipSession.terminate();
              activeCalls.delete(callId);
            }
            return;
          }
          // Notify the other party
          const otherUserId = call.callerId === socket.userId ? call.calleeId : call.callerId;
          const otherConnection = connectedUsers.get(otherUserId);

          if (otherConnection) {
            io.to(otherConnection.socketId).emit('call-ended', {
              callId,
              reason: 'disconnection'
            });
          }

          activeCalls.delete(callId);

          // Update database. Never let a failed write escape: an unhandled
          // rejection here would take the whole server down.
          Promise.resolve()
            .then(() => writeCallRecord(callId, () => db.Call.update(
              { status: 'disconnected', endedAt: new Date() },
              { where: { id: callId } }
            )))
            .catch((error) => {
              logger.error(`Failed to mark call ${callId} disconnected: ${error.message}`);
            });
        }
      });
    });

    // Error handling
    socket.on('error', (error) => {
      logger.error(`Socket error for ${socket.phoneNumber}:`, error);
    });
  });

  return { server, io };
}

/**
 * Start signaling as a standalone server on its own port.
 * Only used when running `node src/signaling-server.js` / `npm run dev:signaling`.
 * The normal entry point (src/index.js) attaches signaling to the API server instead.
 */
async function startSignalingServer() {
  const { server } = createSignalingServer();
  const PORT = process.env.SIGNALING_PORT || 3001;

  return new Promise((resolve) => {
    server.listen(PORT, () => {
      logger.info(`Signaling Server listening on port ${PORT}`);
      resolve(server);
    });
  });
}

/**
 * Attach signaling to an existing HTTP server (shared with the REST API).
 * Returns the Socket.IO instance.
 */
function attachSignalingServer(httpServer) {
  const { io } = createSignalingServer(httpServer);
  return io;
}

if (require.main === module) {
  require('dotenv').config();
  startSignalingServer();
}

module.exports = startSignalingServer;
module.exports.createSignalingServer = createSignalingServer;
module.exports.attachSignalingServer = attachSignalingServer;
module.exports.connectedUsers = connectedUsers;
module.exports.activeCalls = activeCalls;
module.exports.transcribedCalls = transcribedCalls;
module.exports.getTranscribedCall = getTranscribedCall;
