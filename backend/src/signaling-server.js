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

function createSignalingServer() {
  const server = http.createServer();

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
          // User offline - send VoIP push notification
          const voipToken = await db.VoipToken.findOne({
            where: { userId: recipient.id },
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

    // WebRTC Signaling - ICE Candidates
    socket.on('ice-candidate', (data) => {
      const { callId, candidate, to } = data;
      const call = activeCalls.get(callId);

      if (!call) {
        return;
      }

      // Forward ICE candidate to the other peer
      const recipientId = to === call.callerPhone ? call.calleeId : call.callerId;
      const recipientConnection = connectedUsers.get(recipientId);

      if (recipientConnection) {
        io.to(recipientConnection.socketId).emit('ice-candidate', {
          callId,
          candidate,
          from: socket.phoneNumber
        });
        logger.debug(`ICE candidate forwarded for call ${callId}`);
      }
    });

    // WebRTC Signaling - SDP Offer
    socket.on('offer', (data) => {
      const { callId, sdp, to } = data;
      const call = activeCalls.get(callId);

      if (!call) {
        socket.emit('call-error', { callId, error: 'Call not found' });
        return;
      }

      // Forward offer to callee
      const recipientConnection = connectedUsers.get(call.calleeId);
      if (recipientConnection) {
        io.to(recipientConnection.socketId).emit('offer', {
          callId,
          sdp,
          from: socket.phoneNumber,
          hasVideo: call.hasVideo
        });
        logger.debug(`SDP offer forwarded for call ${callId}`);
      }
    });

    // WebRTC Signaling - SDP Answer
    socket.on('answer', (data) => {
      const { callId, sdp } = data;
      const call = activeCalls.get(callId);

      if (!call) {
        return;
      }

      // Forward answer to caller
      const callerConnection = connectedUsers.get(call.callerId);
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

async function startSignalingServer() {
  const { server, io } = createSignalingServer();
  const PORT = process.env.SIGNALING_PORT || 3001;

  return new Promise((resolve) => {
    server.listen(PORT, () => {
      logger.info(`Signaling Server listening on port ${PORT}`);
      resolve(server);
    });
  });
}

module.exports = startSignalingServer;
module.exports.createSignalingServer = createSignalingServer;
module.exports.connectedUsers = connectedUsers;
module.exports.activeCalls = activeCalls;
