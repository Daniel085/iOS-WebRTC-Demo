/**
 * VoIP Push Notification Service
 * Sends VoIP push notifications to iOS devices
 */

const apn = require('@parse/node-apn');
const logger = require('../utils/logger');

let apnProvider = null;

/**
 * Initialize APN provider
 */
function initializeApnProvider() {
  if (apnProvider) {
    return apnProvider;
  }

  const apnOptions = {
    token: process.env.APN_AUTH_METHOD === 'token' ? {
      key: process.env.APN_KEY_PATH,
      keyId: process.env.APN_KEY_ID,
      teamId: process.env.APN_TEAM_ID
    } : null,
    cert: process.env.APN_AUTH_METHOD === 'cert' ? process.env.APN_CERT_PATH : null,
    key: process.env.APN_AUTH_METHOD === 'cert' ? process.env.APN_KEY_PATH : null,
    production: process.env.NODE_ENV === 'production'
  };

  // Remove null values
  Object.keys(apnOptions).forEach(key => {
    if (apnOptions[key] === null) {
      delete apnOptions[key];
    }
  });

  try {
    apnProvider = new apn.Provider(apnOptions);
    logger.info('APN Provider initialized successfully');
  } catch (error) {
    logger.error('Failed to initialize APN Provider:', error);
    apnProvider = null;
  }

  return apnProvider;
}

/**
 * Send VoIP push notification
 *
 * @param {string} deviceToken - The VoIP push token
 * @param {object} payload - Call data (callId, caller, hasVideo)
 */
async function sendVoIPPush(deviceToken, payload) {
  try {
    // In development mode without APNs configured, log instead of sending
    if (!process.env.APN_KEY_PATH && !process.env.APN_CERT_PATH) {
      logger.info('[MOCK VoIP Push] Would send push notification:', {
        token: deviceToken.substring(0, 10) + '...',
        payload
      });
      console.log('═══════════════════════════════════════');
      console.log(`📲 VoIP PUSH NOTIFICATION`);
      console.log(`Device Token: ${deviceToken.substring(0, 20)}...`);
      console.log(`Call ID: ${payload.callId}`);
      console.log(`Caller: ${payload.caller}`);
      console.log(`Has Video: ${payload.hasVideo ? 'Yes' : 'No'}`);
      console.log('═══════════════════════════════════════');
      return { success: true, mock: true };
    }

    const provider = initializeApnProvider();

    if (!provider) {
      throw new Error('APN Provider not initialized');
    }

    const notification = new apn.Notification();

    // VoIP notifications use 'voip' type
    notification.topic = process.env.VOIP_BUNDLE_ID || 'com.yourcompany.webrtcdialer.voip';
    notification.pushType = 'voip';

    // VoIP notifications must have priority 10 (immediate)
    notification.priority = 10;

    // Payload for VoIP push
    notification.payload = {
      callId: payload.callId,
      caller: payload.caller,
      callerName: payload.callerName || payload.caller,
      hasVideo: payload.hasVideo || false,
      timestamp: new Date().toISOString()
    };

    // VoIP pushes don't have sound, badge, or alert
    // The app handles the notification silently

    // Send notification
    const result = await provider.send(notification, deviceToken);

    if (result.failed && result.failed.length > 0) {
      logger.error('VoIP push failed:', result.failed[0].response);
      throw new Error('Failed to send VoIP push');
    }

    logger.info(`VoIP push sent successfully to ${deviceToken.substring(0, 10)}...`);
    return { success: true, result };

  } catch (error) {
    logger.error('Error sending VoIP push:', error);
    throw error;
  }
}

/**
 * Send VoIP push to multiple devices
 */
async function sendVoIPPushToMultiple(deviceTokens, payload) {
  const results = await Promise.allSettled(
    deviceTokens.map(token => sendVoIPPush(token, payload))
  );

  const successful = results.filter(r => r.status === 'fulfilled').length;
  const failed = results.filter(r => r.status === 'rejected').length;

  logger.info(`VoIP push batch: ${successful} successful, ${failed} failed`);

  return {
    successful,
    failed,
    results
  };
}

/**
 * Shutdown APN provider
 */
function shutdown() {
  if (apnProvider) {
    apnProvider.shutdown();
    logger.info('APN Provider shut down');
  }
}

module.exports = {
  sendVoIPPush,
  sendVoIPPushToMultiple,
  shutdown
};
