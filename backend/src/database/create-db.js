/**
 * Database Creation Script
 * Creates the database if it doesn't exist
 */

require('dotenv').config();
const { Client } = require('pg');
const logger = require('../utils/logger');

async function createDatabase() {
  const dbName = process.env.DB_NAME || 'webrtc_dialer';

  // Connect to postgres database to create our database
  const client = new Client({
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 5432,
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'postgres',
    database: 'postgres' // Connect to default postgres database
  });

  try {
    await client.connect();
    logger.info('Connected to PostgreSQL');

    // Check if database exists
    const checkDb = await client.query(
      "SELECT 1 FROM pg_database WHERE datname = $1",
      [dbName]
    );

    if (checkDb.rows.length === 0) {
      // Create database
      await client.query(`CREATE DATABASE ${dbName}`);
      logger.info(`✓ Database '${dbName}' created successfully`);
    } else {
      logger.info(`Database '${dbName}' already exists`);
    }

    await client.end();
    process.exit(0);

  } catch (error) {
    logger.error('Error creating database:', error);
    await client.end();
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  createDatabase();
}

module.exports = createDatabase;
