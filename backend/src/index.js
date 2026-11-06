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

// SKIP_DATABASE=true swaps the Sequelize models for in-memory mocks (nothing
// survives a restart). SKIP_DATABASE=false uses PostgreSQL via the DB_* variables;
// see README.md "Setup Database" for the local Postgres instructions.
const SKIP_DATABASE = process.env.SKIP_DATABASE === 'true';

async function startServers() {
  try {
    // Test database connection
    if (!SKIP_DATABASE) {
      try {
        await db.sequelize.authenticate();
      } catch (error) {
        const { host, port, database, username } = db.sequelize.config;
        const reason = error.message || (error.parent && error.parent.code) || error.name;
        logger.error(`✗ Could not connect to PostgreSQL at ${host}:${port}/${database} as ${username}: ${reason}`);
        logger.error('  Start Postgres and create the database (see backend/README.md "Setup Database"), or set SKIP_DATABASE=true for in-memory mode.');
        throw error;
      }
      logger.info('✓ Database connection established successfully');

      // Create any missing tables/indexes. The models use the same snake_case
      // columns as src/database/migrations, so sync() and `npm run db:migrate`
      // produce the same schema. In production run the migrations instead.
      if (process.env.NODE_ENV !== 'production') {
        await db.sequelize.sync({ alter: false });
        logger.info('✓ Database models synchronized');
      }
    } else {
      logger.warn('⚠️  Running WITHOUT database (SKIP_DATABASE=true)');
      logger.warn('⚠️  User data will NOT persist. For production, set up PostgreSQL.');
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
