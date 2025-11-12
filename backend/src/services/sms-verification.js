/**
 * SMS Verification Service
 * Handles sending and verifying SMS codes
 * Supports Twilio, AWS SNS, and Mock mode for development
 */

const logger = require('../utils/logger');

// Choose SMS provider based on environment
const SMS_PROVIDER = process.env.SMS_PROVIDER || 'mock'; // 'twilio', 'aws-sns', 'firebase', or 'mock'

/**
 * Send verification code
 */
async function sendVerificationCode(phoneNumber) {
  try {
    switch (SMS_PROVIDER) {
      case 'twilio':
        return await sendViaTwilio(phoneNumber);
      case 'aws-sns':
        return await sendViaAwsSns(phoneNumber);
      case 'firebase':
        return await sendViaFirebase(phoneNumber);
      case 'mock':
      default:
        return await sendViaMock(phoneNumber);
    }
  } catch (error) {
    logger.error('Error sending verification code:', error);
    throw new Error('Failed to send verification code');
  }
}

/**
 * Verify code
 */
async function verifyCode(phoneNumber, code) {
  try {
    switch (SMS_PROVIDER) {
      case 'twilio':
        return await verifyViaTwilio(phoneNumber, code);
      case 'aws-sns':
        return await verifyViaAwsSns(phoneNumber, code);
      case 'firebase':
        return await verifyViaFirebase(phoneNumber, code);
      case 'mock':
      default:
        return await verifyViaMock(phoneNumber, code);
    }
  } catch (error) {
    logger.error('Error verifying code:', error);
    return false;
  }
}

// ===== TWILIO IMPLEMENTATION =====

async function sendViaTwilio(phoneNumber) {
  const twilio = require('twilio');
  const client = twilio(
    process.env.TWILIO_ACCOUNT_SID,
    process.env.TWILIO_AUTH_TOKEN
  );

  const verification = await client.verify.v2
    .services(process.env.TWILIO_VERIFY_SERVICE_SID)
    .verifications
    .create({
      to: phoneNumber,
      channel: 'sms'
    });

  logger.info(`Twilio verification sent to ${phoneNumber}: ${verification.status}`);
  return verification;
}

async function verifyViaTwilio(phoneNumber, code) {
  const twilio = require('twilio');
  const client = twilio(
    process.env.TWILIO_ACCOUNT_SID,
    process.env.TWILIO_AUTH_TOKEN
  );

  const check = await client.verify.v2
    .services(process.env.TWILIO_VERIFY_SERVICE_SID)
    .verificationChecks
    .create({
      to: phoneNumber,
      code: code
    });

  logger.info(`Twilio verification check for ${phoneNumber}: ${check.status}`);
  return check.status === 'approved';
}

// ===== AWS SNS IMPLEMENTATION =====

async function sendViaAwsSns(phoneNumber) {
  const AWS = require('aws-sdk');
  const sns = new AWS.SNS({
    region: process.env.AWS_REGION || 'us-east-1',
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
  });

  // Generate 6-digit code
  const code = Math.floor(100000 + Math.random() * 900000).toString();

  // Store code in cache (use Redis in production)
  const cache = require('../utils/cache');
  await cache.set(`sms_code_${phoneNumber}`, code, 300); // 5 minutes TTL

  const params = {
    Message: `Your verification code is: ${code}`,
    PhoneNumber: phoneNumber,
    MessageAttributes: {
      'AWS.SNS.SMS.SMSType': {
        DataType: 'String',
        StringValue: 'Transactional'
      }
    }
  };

  const result = await sns.publish(params).promise();
  logger.info(`AWS SNS verification sent to ${phoneNumber}: ${result.MessageId}`);
  return result;
}

async function verifyViaAwsSns(phoneNumber, code) {
  const cache = require('../utils/cache');
  const storedCode = await cache.get(`sms_code_${phoneNumber}`);

  if (storedCode === code) {
    await cache.del(`sms_code_${phoneNumber}`);
    return true;
  }

  return false;
}

// ===== FIREBASE IMPLEMENTATION =====

async function sendViaFirebase(phoneNumber) {
  // Firebase Phone Auth is typically handled on the client side
  // This is a placeholder for server-side implementation
  logger.warn('Firebase SMS: Should be handled client-side');
  return { status: 'sent' };
}

async function verifyViaFirebase(phoneNumber, code) {
  // Firebase verification is handled client-side
  logger.warn('Firebase SMS: Should be handled client-side');
  return true;
}

// ===== MOCK IMPLEMENTATION (Development Only) =====

const mockCodes = new Map(); // In-memory storage for development

async function sendViaMock(phoneNumber) {
  // Generate a 6-digit code
  const code = Math.floor(100000 + Math.random() * 900000).toString();

  // Store code (in production, use Redis)
  mockCodes.set(phoneNumber, {
    code,
    expiresAt: Date.now() + 5 * 60 * 1000 // 5 minutes
  });

  logger.info(`[MOCK SMS] Code for ${phoneNumber}: ${code}`);
  console.log('═══════════════════════════════════════');
  console.log(`📱 SMS VERIFICATION CODE`);
  console.log(`Phone: ${phoneNumber}`);
  console.log(`Code: ${code}`);
  console.log(`Expires in: 5 minutes`);
  console.log('═══════════════════════════════════════');

  return { status: 'sent', code }; // In production, don't return the code!
}

async function verifyViaMock(phoneNumber, code) {
  const stored = mockCodes.get(phoneNumber);

  if (!stored) {
    logger.warn(`[MOCK SMS] No code found for ${phoneNumber}`);
    return false;
  }

  if (Date.now() > stored.expiresAt) {
    logger.warn(`[MOCK SMS] Code expired for ${phoneNumber}`);
    mockCodes.delete(phoneNumber);
    return false;
  }

  if (stored.code === code) {
    logger.info(`[MOCK SMS] Code verified for ${phoneNumber}`);
    mockCodes.delete(phoneNumber);
    return true;
  }

  logger.warn(`[MOCK SMS] Invalid code for ${phoneNumber}`);
  return false;
}

module.exports = {
  sendVerificationCode,
  verifyCode
};
