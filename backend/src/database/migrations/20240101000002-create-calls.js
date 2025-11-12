'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.createTable('calls', {
      id: {
        type: Sequelize.UUID,
        defaultValue: Sequelize.UUIDV4,
        primaryKey: true
      },
      callerId: {
        type: Sequelize.UUID,
        allowNull: false,
        references: {
          model: 'users',
          key: 'id'
        },
        onUpdate: 'CASCADE',
        onDelete: 'CASCADE',
        field: 'caller_id'
      },
      calleeId: {
        type: Sequelize.UUID,
        allowNull: false,
        references: {
          model: 'users',
          key: 'id'
        },
        onUpdate: 'CASCADE',
        onDelete: 'CASCADE',
        field: 'callee_id'
      },
      type: {
        type: Sequelize.ENUM('audio', 'video'),
        allowNull: false,
        defaultValue: 'audio'
      },
      status: {
        type: Sequelize.ENUM('initiated', 'ringing', 'answered', 'rejected', 'ended', 'missed', 'failed', 'disconnected'),
        allowNull: false,
        defaultValue: 'initiated'
      },
      startedAt: {
        type: Sequelize.DATE,
        allowNull: false,
        defaultValue: Sequelize.NOW,
        field: 'started_at'
      },
      answeredAt: {
        type: Sequelize.DATE,
        allowNull: true,
        field: 'answered_at'
      },
      endedAt: {
        type: Sequelize.DATE,
        allowNull: true,
        field: 'ended_at'
      },
      duration: {
        type: Sequelize.INTEGER,
        allowNull: true
      },
      createdAt: {
        type: Sequelize.DATE,
        defaultValue: Sequelize.NOW,
        field: 'created_at'
      },
      updatedAt: {
        type: Sequelize.DATE,
        defaultValue: Sequelize.NOW,
        field: 'updated_at'
      }
    });

    // Add indexes
    await queryInterface.addIndex('calls', ['caller_id']);
    await queryInterface.addIndex('calls', ['callee_id']);
    await queryInterface.addIndex('calls', ['status']);
    await queryInterface.addIndex('calls', ['started_at']);
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.dropTable('calls');
  }
};
