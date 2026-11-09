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

// Store active connections: Map<userId, {socketId, phoneNumber}>
const connectedUsers = new Map();

// Store active calls: Map<callId, {caller, callee, status}>
const activeCalls = new Map();

/**
 * Create the Socket.IO signaling layer.
 *
 * @param {http.Server} [existingServer] - When provided (the default in
 *   src/index.js), signaling is attached to the same HTTP server as the REST
 *   API so everything runs on ONE port. This keeps the backend deployable on
 *   platforms that expose a single port (Fly.io, Render, Railway, Heroku...).
 *   When omitted, a standalone HTTP server is created (used by `npm run dev:signaling`).
 */
function createSignalingServer(existingServer) {
  const server = existingServer || http.createServer();

  const io = new Server(server, {
    cors: {
      origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
      credentials: true
    },
    pingTimeout: 60000,
    pingInterval: 25000
  });

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

    // Register user connection
    socket.on('register', () => {
      connectedUsers.set(socket.userId, {
        socketId: socket.id,
        phoneNumber: socket.phoneNumber,
        connectedAt: new Date()
      });
      logger.info(`User registered: ${socket.phoneNumber}`);

      socket.emit('registered', { success: true, phoneNumber: socket.phoneNumber });

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
        logger.info(`Call initiated: ${socket.phoneNumber} -> ${to} (${callId})`);

        // Find recipient
        const recipient = await db.User.findOne({ where: { phoneNumber: to } });

        if (!recipient) {
          socket.emit('call-error', { callId, error: 'User not found' });
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
        await db.Call.create({
          id: callId,
          callerId: socket.userId,
          calleeId: recipient.id,
          type: hasVideo ? 'video' : 'audio',
          status: 'initiated',
          startedAt: new Date()
        });

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
        await db.Call.update(
          { status: 'answered', answeredAt: new Date() },
          { where: { id: callId } }
        );

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

        // Notify caller
        const callerConnection = connectedUsers.get(call.callerId);
        if (callerConnection) {
          io.to(callerConnection.socketId).emit('call-rejected', {
            callId,
            by: socket.phoneNumber,
            reason: reason || 'declined'
          });
        }

        // Update database
        await db.Call.update(
          { status: 'rejected', endedAt: new Date() },
          { where: { id: callId } }
        );

        activeCalls.delete(callId);
        logger.info(`Call rejected: ${callId}`);
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

        // Notify the other party
        const otherUserId = call.callerId === socket.userId ? call.calleeId : call.callerId;
        const otherConnection = connectedUsers.get(otherUserId);

        if (otherConnection) {
          io.to(otherConnection.socketId).emit('call-ended', {
            callId,
            by: socket.phoneNumber
          });
        }

        // Update database
        await db.Call.update(
          { status: 'ended', endedAt: new Date() },
          { where: { id: callId } }
        );

        activeCalls.delete(callId);
        logger.info(`Call ended: ${callId}`);
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

    // Handle disconnection
    socket.on('disconnect', (reason) => {
      logger.info(`Client disconnected: ${socket.phoneNumber} (${reason})`);

      // Remove from connected users
      connectedUsers.delete(socket.userId);

      // End any active calls for this user
      activeCalls.forEach(async (call, callId) => {
        if (call.callerId === socket.userId || call.calleeId === socket.userId) {
          // Notify the other party
          const otherUserId = call.callerId === socket.userId ? call.calleeId : call.callerId;
          const otherConnection = connectedUsers.get(otherUserId);

          if (otherConnection) {
            io.to(otherConnection.socketId).emit('call-ended', {
              callId,
              reason: 'disconnection'
            });
          }

          // Update database
          await db.Call.update(
            { status: 'disconnected', endedAt: new Date() },
            { where: { id: callId } }
          );

          activeCalls.delete(callId);
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
