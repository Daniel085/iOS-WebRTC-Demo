/**
 * Call Model
 * Represents a call between two users
 */

module.exports = (sequelize, DataTypes) => {
  const Call = sequelize.define('Call', {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true
    },
    callerId: {
      type: DataTypes.UUID,
      allowNull: false,
      references: {
        model: 'users',
        key: 'id'
      }
    },
    calleeId: {
      type: DataTypes.UUID,
      allowNull: false,
      references: {
        model: 'users',
        key: 'id'
      }
    },
    type: {
      type: DataTypes.ENUM('audio', 'video'),
      allowNull: false,
      defaultValue: 'audio'
    },
    status: {
      type: DataTypes.ENUM('initiated', 'ringing', 'answered', 'rejected', 'ended', 'missed', 'failed', 'disconnected'),
      allowNull: false,
      defaultValue: 'initiated'
    },
    startedAt: {
      type: DataTypes.DATE,
      allowNull: false,
      defaultValue: DataTypes.NOW
    },
    answeredAt: {
      type: DataTypes.DATE,
      allowNull: true
    },
    endedAt: {
      type: DataTypes.DATE,
      allowNull: true
    },
    duration: {
      type: DataTypes.INTEGER, // Duration in seconds
      allowNull: true
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
    tableName: 'calls',
    timestamps: true,
    indexes: [
      {
        fields: ['callerId']
      },
      {
        fields: ['calleeId']
      },
      {
        fields: ['status']
      },
      {
        fields: ['startedAt']
      }
    ],
    hooks: {
      beforeUpdate: (call) => {
        // Calculate duration if call has ended
        if (call.endedAt && call.answeredAt) {
          const duration = Math.floor((call.endedAt - call.answeredAt) / 1000);
          call.duration = duration;
        }
      }
    }
  });

  return Call;
};
