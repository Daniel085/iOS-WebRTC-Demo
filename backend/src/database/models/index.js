/**
 * Database Models Index
 * Initializes Sequelize and loads all models
 */

const { Sequelize } = require('sequelize');
const logger = require('../../utils/logger');

// Check if we should skip database
if (process.env.SKIP_DATABASE === 'true') {
  logger.info('Using mock database (SKIP_DATABASE=true)');

  // Mock database for development without PostgreSQL
  const mockUsers = new Map();
  const mockVoipTokens = [];
  const matchesWhere = (row, where) =>
    Object.entries(where).every(([key, value]) => row[key] === value);

  const db = {
    User: {
      findOne: async ({ where }) => {
        const user = mockUsers.get(where.phoneNumber);
        return user || null;
      },
      create: async (data) => {
        const user = {
          id: `mock-${Date.now()}`,
          phoneNumber: data.phoneNumber,
          displayName: data.displayName || null,
          isActive: data.isActive !== false,
          createdAt: data.createdAt || new Date(),
          lastLoginAt: null,
          update: async (updates) => {
            Object.assign(user, updates);
            mockUsers.set(user.phoneNumber, user);
            return user;
          }
        };
        mockUsers.set(user.phoneNumber, user);
        return user;
      },
      findByPk: async (id) => {
        for (const user of mockUsers.values()) {
          if (user.id === id) return user;
        }
        return null;
      }
    },
    RefreshToken: {
      create: async () => ({}),
      findOne: async () => null,
      update: async () => ({})
    },
    VoipToken: {
      // In-memory token store so VoIP pushes work without PostgreSQL.
      create: async (data) => {
        const record = {
          id: `mock-voip-${Date.now()}-${mockVoipTokens.length}`,
          userId: data.userId,
          token: data.token,
          deviceId: data.deviceId || null,
          isActive: data.isActive !== false,
          createdAt: new Date(),
          updatedAt: new Date(),
          update: async (updates) => {
            Object.assign(record, updates, { updatedAt: new Date() });
            return record;
          }
        };
        mockVoipTokens.push(record);
        return record;
      },
      findOne: async ({ where = {} } = {}) => {
        const matches = mockVoipTokens
          .filter((t) => t.isActive && matchesWhere(t, where))
          .sort((a, b) => b.createdAt - a.createdAt);
        return matches[0] || null;
      },
      update: async (updates, { where = {} } = {}) => {
        let count = 0;
        for (const t of mockVoipTokens) {
          if (matchesWhere(t, where)) {
            Object.assign(t, updates, { updatedAt: new Date() });
            count++;
          }
        }
        return [count];
      },
      destroy: async ({ where = {} } = {}) => {
        const before = mockVoipTokens.length;
        for (let i = mockVoipTokens.length - 1; i >= 0; i--) {
          if (matchesWhere(mockVoipTokens[i], where)) mockVoipTokens.splice(i, 1);
        }
        return before - mockVoipTokens.length;
      }
    },
    Call: {
      create: async () => ({}),
      findAll: async () => [],
      update: async () => ({})
    },
    sequelize: null,
    Sequelize: null
  };

  module.exports = db;
} else {
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
}
