// Unit tests for the Claude call-summary service, with a stubbed SDK client.
const {
  summarizeCall,
  renderTranscript,
  setClientForTesting,
  SummaryRefusedError,
  SummaryUnavailableError,
  MODEL
} = require('../src/services/call-summary');
const { parseTranscript } = require('../src/routes/calls');

const transcript = [
  { speaker: 'me', text: 'Could you send the revised quote?', startedAt: '2026-11-09T10:00:00.000Z' },
  { speaker: 'peer', text: 'Yes, by Wednesday afternoon.', startedAt: '2026-11-09T10:01:05.000Z' }
];

function stubReturning(response) {
  const calls = [];
  setClientForTesting({
    beta: {
      messages: {
        create: async (params) => {
          calls.push(params);
          return response;
        }
      }
    }
  });
  return calls;
}

afterEach(() => setClientForTesting(null));

test('renders speaker labels and relative timestamps', () => {
  expect(renderTranscript(transcript)).toBe(
    '[0:00] You: Could you send the revised quote?\n[1:05] Them: Yes, by Wednesday afternoon.'
  );
});

test('sends a structured-output request and parses the JSON result', async () => {
  const calls = stubReturning({
    stop_reason: 'end_turn',
    content: [{ type: 'text', text: JSON.stringify({ summary: 'You asked for the quote.', actionItems: ['They: email the quote by Wednesday'], keyPoints: ['a', 'b', 'c', 'd', 'e', 'f'] }) }]
  });

  const result = await summarizeCall({ transcript, otherPartyPhone: '+15550000002' });

  expect(result).toEqual({
    summary: 'You asked for the quote.',
    actionItems: ['They: email the quote by Wednesday'],
    keyPoints: ['a', 'b', 'c', 'd', 'e']
  });
  const params = calls[0];
  expect(params.model).toBe(MODEL);
  expect(params.output_config.format.type).toBe('json_schema');
  expect(params.output_config.format.schema.required).toEqual(['summary', 'actionItems', 'keyPoints']);
  expect(params.fallbacks).toBe('default');
  expect(params.betas).toEqual(['server-side-fallback-2026-07-01']);
  expect(params.thinking).toBeUndefined();
  expect(params.messages[0].content).toContain('+15550000002');
  expect(params.messages[0].content).toContain('Them: Yes, by Wednesday afternoon.');
});

test('maps a refusal to SummaryRefusedError', async () => {
  stubReturning({ stop_reason: 'refusal', stop_details: { category: 'general_harms' }, content: [] });
  await expect(summarizeCall({ transcript })).rejects.toBeInstanceOf(SummaryRefusedError);
});

test('maps invalid JSON to SummaryUnavailableError', async () => {
  stubReturning({ stop_reason: 'end_turn', content: [{ type: 'text', text: 'not json' }] });
  await expect(summarizeCall({ transcript })).rejects.toBeInstanceOf(SummaryUnavailableError);
});

test('reports not configured without credentials', async () => {
  const saved = { key: process.env.ANTHROPIC_API_KEY, token: process.env.ANTHROPIC_AUTH_TOKEN };
  delete process.env.ANTHROPIC_API_KEY;
  delete process.env.ANTHROPIC_AUTH_TOKEN;
  try {
    await expect(summarizeCall({ transcript })).rejects.toThrow(/not configured/);
  } finally {
    if (saved.key !== undefined) process.env.ANTHROPIC_API_KEY = saved.key;
    if (saved.token !== undefined) process.env.ANTHROPIC_AUTH_TOKEN = saved.token;
  }
});

test('validates transcripts from the client', () => {
  expect(parseTranscript({ transcript: [] })).toBeNull();
  expect(parseTranscript({ transcript: [{ speaker: 'boss', text: 'hi' }] })).toBeNull();
  expect(parseTranscript({ transcript: [{ speaker: 'me', text: '   ' }] })).toBeNull();
  expect(parseTranscript({ transcript: [{ speaker: 'me', text: ' hi ', startedAt: 'x' }] })).toEqual([
    { speaker: 'me', text: 'hi', startedAt: 'x' }
  ]);
});
