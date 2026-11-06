/**
 * Main Entry Point
 * Starts the REST API and the Socket.IO signaling layer on ONE HTTP server/port.
 *
 * A single port keeps the backend deployable on platforms that expose exactly
 * one port per service (Fly.io, Render, Railway, Heroku) and lets the iOS app
 * use one base URL for both REST (http[s]://host) and signaling (ws[s]://host).
 */

require('dotenv').config();
const http = require('http');
const logger = require('./utils/logger');

const { createApiServer } = require('./api-server');
const { attachSignalingServer } = require('./signaling-server');

// Import database
const db = require('./database/models');

// Running without PostgreSQL keeps users/calls in memory (lost on restart).
const SKIP_DATABASE = process.env.SKIP_DATABASE === 'true';

// PaaS platforms inject PORT; API_PORT is kept for backwards compatibility.
const PORT = parseInt(process.env.PORT || process.env.API_PORT || '3000', 10);

async function startServers() {
  try {
    if (!SKIP_DATABASE) {
      await db.sequelize.authenticate();
      logger.info('✓ Database connection established successfully');

      // Sync database models (use migrations in production)
      if (process.env.NODE_ENV !== 'production') {
        await db.sequelize.sync({ alter: false });
        logger.info('✓ Database models synchronized');
      }
    } else {
      logger.warn('⚠️  Running WITHOUT database (SKIP_DATABASE=true)');
      logger.warn('⚠️  User data will NOT persist. For production, set up PostgreSQL.');
    }

    if (!process.env.JWT_SECRET || !process.env.JWT_REFRESH_SECRET) {
      throw new Error('JWT_SECRET and JWT_REFRESH_SECRET must be set (see .env.example)');
    }

    if (process.env.SIGNALING_PORT && process.env.SIGNALING_PORT !== String(PORT)) {
      logger.warn(`SIGNALING_PORT=${process.env.SIGNALING_PORT} is ignored: signaling now shares port ${PORT} with the API`);
    }

    const app = createApiServer();
    const server = http.createServer(app);
    const io = attachSignalingServer(server);

    await new Promise((resolve) => server.listen(PORT, '0.0.0.0', resolve));

    logger.info(`✓ API Server running on port ${PORT} (http://0.0.0.0:${PORT})`);
    logger.info(`✓ Signaling Server attached on the same port (Socket.IO path /socket.io)`);
    logger.info('✓ All servers started successfully');
    logger.info(`Environment: ${process.env.NODE_ENV || 'development'}`);

    // Graceful shutdown
    const gracefulShutdown = async (signal) => {
      logger.info(`${signal} received, shutting down gracefully...`);

      io.close();
      server.close(() => {
        logger.info('✓ HTTP server closed');
      });

      if (!SKIP_DATABASE) {
        await db.sequelize.close();
        logger.info('✓ Database connection closed');
      }

      process.exit(0);
    };

    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
    process.on('SIGINT', () => gracefulShutdown('SIGINT'));

  } catch (error) {
    logger.error('Failed to start servers:', error);
    process.exit(1);
  }
}

// Start everything
startServers();
