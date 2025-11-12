/**
 * Main Entry Point
 * Starts both API and Signaling servers
 */

require('dotenv').config();
const logger = require('./utils/logger');

// Import servers
const startApiServer = require('./api-server');
const startSignalingServer = require('./signaling-server');

// Import database
const db = require('./database/models');

async function startServers() {
  try {
    // Test database connection
    await db.sequelize.authenticate();
    logger.info('✓ Database connection established successfully');

    // Sync database models (use migrations in production)
    if (process.env.NODE_ENV !== 'production') {
      await db.sequelize.sync({ alter: false });
      logger.info('✓ Database models synchronized');
    }

    // Start API Server
    const apiServer = await startApiServer();
    const API_PORT = process.env.API_PORT || 3000;
    logger.info(`✓ API Server running on port ${API_PORT}`);

    // Start Signaling Server
    const signalingServer = await startSignalingServer();
    const SIGNALING_PORT = process.env.SIGNALING_PORT || 3001;
    logger.info(`✓ Signaling Server running on port ${SIGNALING_PORT}`);

    logger.info('✓ All servers started successfully');
    logger.info(`Environment: ${process.env.NODE_ENV || 'development'}`);

    // Graceful shutdown
    const gracefulShutdown = async (signal) => {
      logger.info(`${signal} received, shutting down gracefully...`);

      apiServer.close(() => {
        logger.info('✓ API Server closed');
      });

      signalingServer.close(() => {
        logger.info('✓ Signaling Server closed');
      });

      await db.sequelize.close();
      logger.info('✓ Database connection closed');

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
