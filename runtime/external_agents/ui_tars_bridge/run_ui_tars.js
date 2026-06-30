const fs = require('fs');
const { GUIAgent, StatusEnum } = require('@ui-tars/sdk');
const { NutJSOperator } = require('@ui-tars/operator-nut-js');

async function readStdin() {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => {
      data += chunk;
    });
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);
  });
}

async function main() {
  const raw = await readStdin();
  const payload = raw ? JSON.parse(raw) : {};
  const events = [];
  let lastStatus = 'INIT';
  const startedAt = Date.now();
  const abortController = new AbortController();
  const maxDurationMs = Number(payload.maxDurationMs || 120000);
  let didTimeout = false;
  const timeoutHandle = setTimeout(() => {
    didTimeout = true;
    abortController.abort(new Error('bridge_timeout'));
  }, maxDurationMs);
  const quietLogger = {
    log: () => {},
    info: () => {},
    warn: () => {},
    error: () => {},
  };

  const agent = new GUIAgent({
    model: payload.model,
    operator: new NutJSOperator(),
    signal: abortController.signal,
    logger: quietLogger,
    maxLoopCount: Number(payload.maxLoopCount || 8),
    loopIntervalInMs: Number(payload.loopIntervalInMs || 250),
    onData: ({ data }) => {
      lastStatus = data.status || lastStatus;
      events.push({
        type: 'data',
        status: data.status,
        loopCount: data.loopCnt,
        conversations: data.conversations || [],
      });
    },
    onError: ({ data, error }) => {
      events.push({
        type: 'error',
        status: data?.status,
        error: String(error?.message || error || 'unknown_error'),
      });
    },
  });

  try {
    await agent.run(String(payload.instruction || ''));
    clearTimeout(timeoutHandle);
    const status =
      lastStatus === StatusEnum.END || lastStatus === 'END' ? 'success' : 'failed';
    process.stdout.write(
      JSON.stringify({
        status,
        reason: status === 'success' ? null : 'agent_incomplete',
        finalStatus: lastStatus,
        durationMs: Date.now() - startedAt,
        eventCount: events.length,
        events,
      }),
    );
  } catch (error) {
    clearTimeout(timeoutHandle);
    process.stdout.write(
      JSON.stringify({
        status: 'failed',
        finalStatus: lastStatus,
        reason: didTimeout ? 'timeout' : 'agent_error',
        error: String(error?.message || error || 'unknown_error'),
        durationMs: Date.now() - startedAt,
        eventCount: events.length,
        events,
      }),
    );
  }
}

main();
