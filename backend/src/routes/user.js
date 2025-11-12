/**
 * User Routes
 * Handles user profile and VoIP token management
 */

const express = require('express');
const router = express.Router();
const Joi = require('joi');

const db = require('../database/models');
const { authenticate } = require('../middleware/auth');
const logger = require('../utils/logger');

// All routes require authentication
router.use(authenticate);

/**
 * GET /api/user/profile
 * Get current user profile
 */
router.get('/profile', async (req, res, next) => {
  try {
    const user = await db.User.findByPk(req.userId, {
      attributes: ['id', 'phoneNumber', 'displayName', 'createdAt', 'lastLoginAt']
    });

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found'
      });
    }

    res.json({
      success: true,
      user
    });

  } catch (error) {
    logger.error('Error fetching profile:', error);
    next(error);
  }
});

/**
 * PUT /api/user/profile
 * Update user profile
 */
router.put('/profile', async (req, res, next) => {
  try {
    const schema = Joi.object({
      displayName: Joi.string().min(1).max(100).optional()
    });

    const { error, value } = schema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: error.details[0].message
      });
    }

    const user = await db.User.findByPk(req.userId);

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found'
      });
    }

    await user.update(value);

    res.json({
      success: true,
      user: {
        id: user.id,
        phoneNumber: user.phoneNumber,
        displayName: user.displayName
      }
    });

  } catch (error) {
    logger.error('Error updating profile:', error);
    next(error);
  }
});

/**
 * POST /api/user/voip-token
 * Register VoIP push token
 */
router.post('/voip-token', async (req, res, next) => {
  try {
    const schema = Joi.object({
      token: Joi.string().required(),
      deviceId: Joi.string().optional()
    });

    const { error, value } = schema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: error.details[0].message
      });
    }

    const { token, deviceId } = value;

    // Check if token already exists
    let voipToken = await db.VoipToken.findOne({
      where: {
        userId: req.userId,
        token
      }
    });

    if (voipToken) {
      // Update existing token
      await voipToken.update({
        deviceId,
        updatedAt: new Date()
      });
      logger.info(`VoIP token updated for user ${req.userId}`);
    } else {
      // Create new token
      voipToken = await db.VoipToken.create({
        userId: req.userId,
        token,
        deviceId,
        isActive: true
      });
      logger.info(`VoIP token registered for user ${req.userId}`);
    }

    res.json({
      success: true,
      message: 'VoIP token registered successfully'
    });

  } catch (error) {
    logger.error('Error registering VoIP token:', error);
    next(error);
  }
});

/**
 * DELETE /api/user/voip-token
 * Unregister VoIP push token
 */
router.delete('/voip-token', async (req, res, next) => {
  try {
    const { token } = req.body;

    if (!token) {
      return res.status(400).json({
        success: false,
        error: 'Token required'
      });
    }

    await db.VoipToken.update(
      { isActive: false },
      {
        where: {
          userId: req.userId,
          token
        }
      }
    );

    logger.info(`VoIP token deactivated for user ${req.userId}`);

    res.json({
      success: true,
      message: 'VoIP token unregistered successfully'
    });

  } catch (error) {
    logger.error('Error unregistering VoIP token:', error);
    next(error);
  }
});

/**
 * GET /api/user/call-history
 * Get user's call history
 */
router.get('/call-history', async (req, res, next) => {
  try {
    const limit = parseInt(req.query.limit) || 50;
    const offset = parseInt(req.query.offset) || 0;

    const calls = await db.Call.findAll({
      where: {
        [db.Sequelize.Op.or]: [
          { callerId: req.userId },
          { calleeId: req.userId }
        ]
      },
      include: [
        {
          model: db.User,
          as: 'caller',
          attributes: ['id', 'phoneNumber', 'displayName']
        },
        {
          model: db.User,
          as: 'callee',
          attributes: ['id', 'phoneNumber', 'displayName']
        }
      ],
      order: [['startedAt', 'DESC']],
      limit,
      offset
    });

    const total = await db.Call.count({
      where: {
        [db.Sequelize.Op.or]: [
          { callerId: req.userId },
          { calleeId: req.userId }
        ]
      }
    });

    res.json({
      success: true,
      calls,
      pagination: {
        total,
        limit,
        offset,
        hasMore: offset + calls.length < total
      }
    });

  } catch (error) {
    logger.error('Error fetching call history:', error);
    next(error);
  }
});

/**
 * DELETE /api/user/account
 * Delete user account
 */
router.delete('/account', async (req, res, next) => {
  try {
    const user = await db.User.findByPk(req.userId);

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found'
      });
    }

    // Soft delete - just deactivate
    await user.update({ isActive: false, deletedAt: new Date() });

    // Revoke all refresh tokens
    await db.RefreshToken.update(
      { isRevoked: true },
      { where: { userId: req.userId } }
    );

    // Deactivate VoIP tokens
    await db.VoipToken.update(
      { isActive: false },
      { where: { userId: req.userId } }
    );

    logger.info(`User account deleted: ${req.userId}`);

    res.json({
      success: true,
      message: 'Account deleted successfully'
    });

  } catch (error) {
    logger.error('Error deleting account:', error);
    next(error);
  }
});

module.exports = router;
