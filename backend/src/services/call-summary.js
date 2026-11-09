/**
 * Call Summary Service
 *
 * Turns a call transcript into a short summary, action items and key points
 * with Claude. The transcript is sent by a participant's phone after the call
 * (each phone transcribed its own side on-device); nothing is stored here.
 *
 * Credentials: the Anthropic SDK reads ANTHROPIC_API_KEY (or another
 * supported credential source) from the environment.
 */

const Anthropic = require('@anthropic-ai/sdk');
const logger = require('../utils/logger');

const MODEL = process.env.SUMMARY_MODEL || 'claude-opus-5-5';

const SUMMARY_SCHEMA = {
  type: 'object',
  properties: {
    summary: {
      type: 'string',
      description: 'Two to four sentences addressed to the reader as "you", covering what the call was about and what was decided.'
    },
    actionItems: {
      type: 'array',
      items: { type: 'string' },
      description: 'Concrete commitments, each starting with who owns it ("You:" or "They:"), with any deadline mentioned.'
    },
    keyPoints: {
      type: 'array',
      items: { type: 'string' },
      description: 'Up to five specific facts worth remembering: dates, times, amounts, names, decisions.'
    }
  },
  required: ['summary', 'actionItems', 'keyPoints'],
  additionalProperties: false
};

const SYSTEM_PROMPT = `You write the notes a person would want after a phone call, from that person's point of view.

The transcript comes from on-device speech recognition, one line per phrase, labelled "You" (the reader) or "Them" (the other person). Recognition errors are common: infer the intended words from context, and never quote a garbled phrase as if it were exact. If one side's lines are missing, summarize from what is there and do not speculate about what wasn't captured.

Address the reader as "you" and refer to the other person as "they" (or by name if the transcript makes their name clear). Only include action items someone actually committed to or was asked to do; leave the list empty when there are none. Keep key points to concrete details such as dates, times, amounts and decisions. If the call has no substantive content, say so in one sentence and return empty lists.`;

class SummaryUnavailableError extends Error {}
class SummaryRefusedError extends Error {}

let client = null;

/**
 * Lazily construct the SDK client so the server starts (and everything else
 * works) without Anthropic credentials. Tests can inject a stub.
 */
function getClient() {
  if (client) return client;
  if (!process.env.ANTHROPIC_API_KEY && !process.env.ANTHROPIC_AUTH_TOKEN) {
    throw new SummaryUnavailableError('Call summaries are not configured on the server (set ANTHROPIC_API_KEY)');
  }
  client = new Anthropic();
  return client;
}

function setClientForTesting(stub) {
  client = stub;
}

/**
 * @param {Array<{speaker: 'me'|'peer', text: string, startedAt?: string}>} transcript
 * @returns {string} transcript rendered as "[m:ss] You: ..." lines
 */
function renderTranscript(transcript) {
  const times = transcript.map((line) => Date.parse(line.startedAt)).filter((t) => !Number.isNaN(t));
  const start = times.length ? Math.min(...times) : null;
  return transcript
    .map((line) => {
      const who = line.speaker === 'me' ? 'You' : 'Them';
      const at = Date.parse(line.startedAt);
      let stamp = '';
      if (start !== null && !Number.isNaN(at)) {
        const seconds = Math.max(0, Math.round((at - start) / 1000));
        stamp = `[${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}] `;
      }
      return `${stamp}${who}: ${line.text}`;
    })
    .join('\n');
}

/**
 * Summarize a call for one participant.
 * @returns {Promise<{summary: string, actionItems: string[], keyPoints: string[]}>}
 */
async function summarizeCall({ transcript, otherPartyPhone }) {
  const anthropic = getClient();
  const rendered = renderTranscript(transcript);
  const context = otherPartyPhone ? `The other person's phone number is ${otherPartyPhone}.\n\n` : '';

  let response;
  try {
    response = await anthropic.beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      output_config: {
        effort: 'low',
        format: { type: 'json_schema', schema: SUMMARY_SCHEMA }
      },
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: 'user',
          content: `${context}<transcript>\n${rendered}\n</transcript>\n\nWrite the call notes.`
        }
      ]
    });
  } catch (error) {
    if (error instanceof Anthropic.AuthenticationError) {
      throw new SummaryUnavailableError('The server\'s Anthropic API key was rejected');
    } else if (error instanceof Anthropic.RateLimitError) {
      throw new SummaryUnavailableError('The summary service is busy; try again shortly');
    } else if (error instanceof Anthropic.APIError) {
      logger.error(`Claude API error ${error.status}: ${error.message}`);
      throw new SummaryUnavailableError('The summary service failed; try again later');
    }
    throw error;
  }

  if (response.stop_reason === 'refusal') {
    logger.warn(`Summary declined (category: ${response.stop_details?.category ?? 'unknown'})`);
    throw new SummaryRefusedError('This call could not be summarized');
  }
  if (response.stop_reason === 'max_tokens') {
    throw new SummaryUnavailableError('The summary was cut off; try again');
  }

  const text = response.content
    .filter((block) => block.type === 'text')
    .map((block) => block.text)
    .join('');

  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (error) {
    logger.error('Summary response was not valid JSON');
    throw new SummaryUnavailableError('The summary service returned an unexpected response');
  }

  return {
    summary: String(parsed.summary || '').trim(),
    actionItems: Array.isArray(parsed.actionItems) ? parsed.actionItems.map(String) : [],
    keyPoints: Array.isArray(parsed.keyPoints) ? parsed.keyPoints.map(String).slice(0, 5) : []
  };
}

module.exports = {
  summarizeCall,
  renderTranscript,
  setClientForTesting,
  SummaryUnavailableError,
  SummaryRefusedError,
  MODEL
};
