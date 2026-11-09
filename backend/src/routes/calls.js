/**
 * Call Routes
 *
 * POST /api/calls/:callId/summary
 *   Body: { transcript: [{ speaker: "me" | "peer", text, startedAt }] }
 *   Summarizes a call the requester took part in, but only if both people
 *   agreed to transcription during that call (recorded by the signaling
 *   server). The transcript is not stored.
 */

const express = require('express');
const { authenticate } = require('../middleware/auth');
const logger = require('../utils/logger');
const { getTranscribedCall } = require('../signaling-server');
const {
  summarizeCall,
  SummaryUnavailableError,
  SummaryRefusedError
} = require('../services/call-summary');

const router = express.Router();

const MAX_LINES = 5000;
const MAX_LINE_LENGTH = 2000;

function parseTranscript(body) {
  const lines = body?.transcript;
  if (!Array.isArray(lines) || lines.length === 0) return null;
  if (lines.length > MAX_LINES) return null;
  const parsed = [];
  for (const line of lines) {
    if (!line || (line.speaker !== 'me' && line.speaker !== 'peer')) return null;
    if (typeof line.text !== 'string') return null;
    const text = line.text.trim().slice(0, MAX_LINE_LENGTH);
    if (!text) continue;
    parsed.push({ speaker: line.speaker, text, startedAt: typeof line.startedAt === 'string' ? line.startedAt : undefined });
  }
  return parsed.length ? parsed : null;
}

router.post('/:callId/summary', authenticate, async (req, res, next) => {
  const { callId } = req.params;
  try {
    const call = getTranscribedCall(callId);
    if (!call || !call.participants.includes(req.userId)) {
      return res.status(404).json({
        success: false,
        error: 'No transcribed call found. Summaries are only available for calls both people agreed to transcribe.'
      });
    }

    const transcript = parseTranscript(req.body);
    if (!transcript) {
      return res.status(400).json({ success: false, error: 'Transcript is missing or invalid' });
    }

    const otherPartyPhone = call.phones[call.participants.find((id) => id !== req.userId)];
    const summary = await summarizeCall({ transcript, otherPartyPhone });
    logger.info(`Summarized call ${callId} for ${req.phoneNumber} (${transcript.length} lines)`);
    return res.json({ success: true, summary });
  } catch (error) {
    if (error instanceof SummaryUnavailableError) {
      return res.status(503).json({ success: false, error: error.message });
    }
    if (error instanceof SummaryRefusedError) {
      return res.status(422).json({ success: false, error: error.message });
    }
    return next(error);
  }
});

module.exports = router;
module.exports.parseTranscript = parseTranscript;
