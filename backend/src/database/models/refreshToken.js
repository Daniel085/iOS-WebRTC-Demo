/**
 * RefreshToken Model
 * Stores refresh tokens for JWT authentication
 */

module.exports = (sequelize, DataTypes) => {
  const RefreshToken = sequelize.define('RefreshToken', {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true
    },
    userId: {
      type: DataTypes.UUID,
      allowNull: false,
      references: {
        model: 'users',
        key: 'id'
      }
    },
    token: {
      type: DataTypes.TEXT,
      allowNull: false
    },
    isRevoked: {
      type: DataTypes.BOOLEAN,
      defaultValue: false
    },
    expiresAt: {
      type: DataTypes.DATE,
      allowNull: false
    },
    createdAt: {
      type: DataTypes.DATE,
      defaultValue: DataTypes.NOW
    },
    updatedAt: {
      type: DataTypes.DATE,
      defaultValue: DataTypes.NOW
    }
  }, {
    tableName: 'refresh_tokens',
    timestamps: true,
    indexes: [
      {
        fields: ['userId']
      },
      {
        unique: true,
        fields: ['token']
      },
      {
        fields: ['isRevoked']
      },
      {
        fields: ['expiresAt']
      }
    ]
  });

  return RefreshToken;
};
