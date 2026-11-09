/**
 * VoipToken Model
 * Stores VoIP push notification tokens for users
 *
 * Column names are snake_case (`underscored: true`) to match the migrations.
 * `token` is unique across all users: an APNs VoIP token identifies a device,
 * so when another account signs in on the same device the row is reassigned
 * (see routes/user.js) rather than duplicated.
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
      },
      onUpdate: 'CASCADE',
      onDelete: 'CASCADE'
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
    underscored: true,
    indexes: [
      {
        fields: ['user_id']
      },
      {
        unique: true,
        fields: ['token']
      },
      {
        fields: ['is_active']
      }
    ]
  });

  return VoipToken;
};
