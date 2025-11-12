/**
 * Authentication Routes
 * Handles phone number verification and JWT token generation
 */

const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const Joi = require('joi');

const db = require('../database/models');
const { sendVerificationCode, verifyCode } = require('../services/sms-verification');
const logger = require('../utils/logger');

// Validation schemas
const sendCodeSchema = Joi.object({
  phoneNumber: Joi.string().pattern(/^\+[1-9]\d{1,14}$/).required()
});

const verifyCodeSchema = Joi.object({
  phoneNumber: Joi.string().pattern(/^\+[1-9]\d{1,14}$/).required(),
  code: Joi.string().length(6).pattern(/^\d+$/).required()
});

/**
 * POST /api/auth/send-code
 * Send verification code to phone number
 */
router.post('/send-code', async (req, res, next) => {
  try {
    // Validate request
    const { error, value } = sendCodeSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: error.details[0].message
      });
    }

    const { phoneNumber } = value;

    // Send verification code via SMS
    await sendVerificationCode(phoneNumber);

    logger.info(`Verification code sent to ${phoneNumber}`);

    res.json({
      success: true,
      message: 'Verification code sent successfully'
    });

  } catch (error) {
    logger.error('Error sending verification code:', error);
    next(error);
  }
});

/**
 * POST /api/auth/verify-code
 * Verify code and return JWT token
 */
router.post('/verify-code', async (req, res, next) => {
  try {
    // Validate request
    const { error, value } = verifyCodeSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: error.details[0].message
      });
    }

    const { phoneNumber, code } = value;

    // Verify the code
    const isValid = await verifyCode(phoneNumber, code);

    if (!isValid) {
      return res.status(401).json({
        success: false,
        error: 'Invalid verification code'
      });
    }

    // Find or create user
    let user = await db.User.findOne({ where: { phoneNumber } });

    if (!user) {
      user = await db.User.create({
        phoneNumber,
        isActive: true,
        createdAt: new Date()
      });
      logger.info(`New user created: ${phoneNumber}`);
    } else {
      await user.update({ lastLoginAt: new Date() });
      logger.info(`User logged in: ${phoneNumber}`);
    }

    // Generate JWT token
    const token = jwt.sign(
      {
        userId: user.id,
        phoneNumber: user.phoneNumber
      },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    // Generate refresh token
    const refreshToken = jwt.sign(
      {
        userId: user.id,
        type: 'refresh'
      },
      process.env.JWT_REFRESH_SECRET,
      { expiresIn: '90d' }
    );

    // Save refresh token
    await db.RefreshToken.create({
      userId: user.id,
      token: refreshToken,
      expiresAt: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)
    });

    res.json({
      success: true,
      token,
      refreshToken,
      user: {
        id: user.id,
        phoneNumber: user.phoneNumber,
        displayName: user.displayName,
        createdAt: user.createdAt
      }
    });

  } catch (error) {
    logger.error('Error verifying code:', error);
    next(error);
  }
});

/**
 * POST /api/auth/refresh
 * Refresh access token using refresh token
 */
router.post('/refresh', async (req, res, next) => {
  try {
    const { refreshToken } = req.body;

    if (!refreshToken) {
      return res.status(400).json({
        success: false,
        error: 'Refresh token required'
      });
    }

    // Verify refresh token
    const decoded = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);

    // Check if token exists in database
    const storedToken = await db.RefreshToken.findOne({
      where: {
        userId: decoded.userId,
        token: refreshToken,
        isRevoked: false
      }
    });

    if (!storedToken || new Date() > storedToken.expiresAt) {
      return res.status(401).json({
        success: false,
        error: 'Invalid or expired refresh token'
      });
    }

    // Get user
    const user = await db.User.findByPk(decoded.userId);

    if (!user || !user.isActive) {
      return res.status(401).json({
        success: false,
        error: 'User not found or inactive'
      });
    }

    // Generate new access token
    const token = jwt.sign(
      {
        userId: user.id,
        phoneNumber: user.phoneNumber
      },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.json({
      success: true,
      token,
      user: {
        id: user.id,
        phoneNumber: user.phoneNumber,
        displayName: user.displayName
      }
    });

  } catch (error) {
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({
        success: false,
        error: 'Invalid refresh token'
      });
    }
    logger.error('Error refreshing token:', error);
    next(error);
  }
});

/**
 * POST /api/auth/logout
 * Revoke refresh token
 */
router.post('/logout', async (req, res, next) => {
  try {
    const { refreshToken } = req.body;

    if (refreshToken) {
      await db.RefreshToken.update(
        { isRevoked: true },
        { where: { token: refreshToken } }
      );
    }

    res.json({
      success: true,
      message: 'Logged out successfully'
    });

  } catch (error) {
    logger.error('Error logging out:', error);
    next(error);
  }
});

module.exports = router;
