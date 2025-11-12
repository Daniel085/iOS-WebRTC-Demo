/**
 * VoipToken Model
 * Stores VoIP push notification tokens for users
 */

module.exports = (sequelize, DataTypes) => {
  const VoipToken = sequelize.define('VoipToken', {
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
    deviceId: {
      type: DataTypes.STRING(255),
      allowNull: true
    },
    isActive: {
      type: DataTypes.BOOLEAN,
      defaultValue: true
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
    tableName: 'voip_tokens',
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
        fields: ['isActive']
      }
    ]
  });

  return VoipToken;
};
