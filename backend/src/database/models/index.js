/**
 * Database Models Index
 * Initializes Sequelize and loads all models
 */

const { Sequelize } = require('sequelize');
const logger = require('../../utils/logger');

// Initialize Sequelize
const sequelize = new Sequelize(
  process.env.DB_NAME || 'webrtc_dialer',
  process.env.DB_USER || 'postgres',
  process.env.DB_PASSWORD || 'postgres',
  {
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 5432,
    dialect: 'postgres',
    logging: process.env.NODE_ENV === 'development' ? (msg) => logger.debug(msg) : false,
    pool: {
      max: 10,
      min: 0,
      acquire: 30000,
      idle: 10000
    }
  }
);

// Import models
const User = require('./user')(sequelize, Sequelize.DataTypes);
const Call = require('./call')(sequelize, Sequelize.DataTypes);
const VoipToken = require('./voipToken')(sequelize, Sequelize.DataTypes);
const RefreshToken = require('./refreshToken')(sequelize, Sequelize.DataTypes);

// Define associations
User.hasMany(Call, { foreignKey: 'callerId', as: 'callsMade' });
User.hasMany(Call, { foreignKey: 'calleeId', as: 'callsReceived' });
User.hasMany(VoipToken, { foreignKey: 'userId' });
User.hasMany(RefreshToken, { foreignKey: 'userId' });

Call.belongsTo(User, { foreignKey: 'callerId', as: 'caller' });
Call.belongsTo(User, { foreignKey: 'calleeId', as: 'callee' });

VoipToken.belongsTo(User, { foreignKey: 'userId' });
RefreshToken.belongsTo(User, { foreignKey: 'userId' });

const db = {
  sequelize,
  Sequelize,
  User,
  Call,
  VoipToken,
  RefreshToken
};

module.exports = db;
