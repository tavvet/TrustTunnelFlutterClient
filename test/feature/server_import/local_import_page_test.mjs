import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

// Exercise the script shipped in the Dart HTML template without a browser or
// third-party packages. The server-side duration is the only interpolation.
const source = readFileSync(
  new URL('../../../lib/feature/server/server_import/service/local_import_page.dart', import.meta.url),
  'utf8',
);
const script = source.match(/<script nonce="\$nonce">([\s\S]*?)<\/script>/)[1];

function openPage({ token = 'test-qr-token', remaining = 300_000, wallClock = 0 } = {}) {
  let elapsed = 0;
  let realElapsed = 0;
  let statusHandler;
  const events = {};
  const requests = [];
  const checks = [];
  const timers = new Set();
  const timeouts = new Set();
  const elements = Object.fromEntries(
    ['import-form', 'code-group', 'code', 'link', 'submit', 'retry', 'feedback', 'expiry'].map((id) => [id, {
      value: '', hidden: id === 'retry', disabled: false, required: id === 'code', textContent: '',
      addEventListener: (type, handler) => { events[type] = handler; },
    }]),
  );
  elements['import-form'].reportValidity = () =>
    (!elements.code.required || /^[0-9]{6}$/.test(elements.code.value)) && elements.link.value !== '';
  const location = { hash: token ? `#token=${token}` : '', pathname: '/' };
  const document = {
    visibilityState: 'visible',
    getElementById: (id) => elements[id],
    addEventListener: (type, handler) => { events[type] = handler; },
  };
  runInNewContext(script.replace('${remaining.inMilliseconds}', String(remaining)), {
    URLSearchParams,
    AbortController,
    location,
    history: { replaceState: () => { location.hash = ''; } },
    document,
    window: { addEventListener: (type, handler) => { events[type] = handler; } },
    Date: { now: () => wallClock + realElapsed },
    performance: { now: () => elapsed },
    setInterval: (callback) => { timers.add(callback); return callback; },
    clearInterval: (callback) => timers.delete(callback),
    setTimeout: (callback) => { timeouts.add(callback); return callback; },
    clearTimeout: (callback) => timeouts.delete(callback),
    fetch: async (url, options) => {
      if (url === '/status') {
        checks.push(options);
        if (statusHandler) return statusHandler(options);
        if (realElapsed >= remaining) throw new Error('TV listener closed');
        return statusReply(remaining - realElapsed);
      }
      assert.equal(url, '/import');
      const body = JSON.parse(options.body);
      requests.push(body);
      const authorized = body.token === 'test-qr-token' || body.code === '123456';
      return {
        ok: authorized,
        status: authorized ? 200 : 401,
        json: async () => ({ ok: authorized, message: authorized ? 'Received' : 'Incorrect code' }),
      };
    },
  });
  return {
    elements, events, requests, checks, location, document,
    advance: async (milliseconds) => {
      elapsed += milliseconds;
      realElapsed += milliseconds;
      timers.forEach((callback) => callback());
      await settle();
    },
    suspendFor: (milliseconds) => { elapsed += milliseconds; realElapsed += milliseconds; },
    sleepFor: (milliseconds) => { realElapsed += milliseconds; },
    setWallClock: (value) => { wallClock = value; },
    setStatusHandler: (handler) => { statusHandler = handler; },
    timeoutChecks: async () => { timeouts.forEach((callback) => callback()); await settle(); },
    submit: () => events.submit({ preventDefault() {} }),
  };
}

const settle = () => new Promise((resolve) => setImmediate(resolve));
const statusReply = (remainingMilliseconds) => ({
  ok: true, status: 200, json: async () => ({ remainingMilliseconds }),
});

test('fresh QR import uses its token without asking for a PIN', async () => {
  const page = openPage();
  await page.events.pageshow({ persisted: false });
  assert.equal(page.checks.length, 0);
  assert.equal(page.elements['code-group'].hidden, true);
  assert.equal(page.elements.code.required, false);
  assert.equal(page.location.hash, '');
  page.elements.link.value = 'tt://?test';
  await page.submit();
  assert.deepEqual(page.requests, [{ token: 'test-qr-token', link: 'tt://?test' }]);
  assert.equal(page.elements['import-form'].hidden, true);
});

test('history restore clears secrets and allows import with the TV PIN', async () => {
  const page = openPage();
  page.elements.link.value = 'tt://?previous-secret';
  page.elements.code.value = '654321';
  page.events.pagehide({ persisted: true });
  await page.events.pageshow({ persisted: true });
  assert.equal(page.checks.length, 1);
  assert.equal(page.elements.link.value, '');
  assert.equal(page.elements.code.value, '');
  assert.equal(page.elements['code-group'].hidden, false);
  assert.equal(page.elements.code.required, true);

  page.elements.link.value = 'tt://?test';
  await page.submit();
  assert.equal(page.requests.length, 0, 'An empty PIN must not consume a pairing attempt');
  page.elements.code.value = '123456';
  await page.submit();
  assert.deepEqual(page.requests, [{ code: '123456', link: 'tt://?test' }]);
  assert.equal(page.elements['import-form'].hidden, true);
});

test('countdown ignores clock offsets and rechecks wall-clock adjustments', async () => {
  for (const wallClock of [-86_400_000, 1_800_000_000_000]) {
    const page = openPage({ remaining: 12_000, wallClock });
    assert.equal(page.elements.submit.disabled, false);
    assert.match(page.elements.expiry.textContent, /0:12/);
    page.setWallClock(wallClock + 3_600_000);
    await page.advance(5000);
    assert.equal(page.elements.submit.disabled, false);
    assert.match(page.elements.expiry.textContent, /0:07/);
    page.setWallClock(wallClock - 3_600_000);
    await page.advance(7000);
    assert.equal(page.elements.submit.disabled, true);
    assert.match(page.elements.feedback.textContent, /expired/);
  }
});

test('restoring an expired page immediately blocks submission', async () => {
  const page = openPage({ remaining: 1000 });
  page.events.pagehide({ persisted: true });
  page.suspendFor(2000);
  await page.events.pageshow({ persisted: true });
  assert.equal(page.elements.submit.disabled, true);
  assert.match(page.elements.feedback.textContent, /expired/);
  page.elements.code.value = '123456';
  page.elements.link.value = 'tt://?test';
  await page.submit();
  assert.equal(page.requests.length, 0);
});

test('completed import stays closed after history restore', async () => {
  const page = openPage({ token: null });
  page.elements.code.value = '123456';
  page.elements.link.value = 'tt://?test';
  await page.submit();
  page.events.pagehide({ persisted: true });
  page.suspendFor(600_000);
  await page.events.pageshow({ persisted: true });
  await page.advance(1000);
  assert.equal(page.elements['import-form'].hidden, true);
  assert.equal(page.elements.submit.disabled, true);
  assert.equal(page.elements.expiry.textContent, 'This session is now closed.');
  await page.submit();
  assert.equal(page.requests.length, 1);
});

test('sleep beyond the session lifetime hides the stale countdown and blocks sending', async () => {
  const page = openPage();
  page.elements.link.value = 'tt://?test';
  page.sleepFor(360_000);
  await page.advance(0);
  assert.equal(page.checks.length, 1);
  assert.equal(page.elements.submit.disabled, true);
  assert.equal(page.elements.retry.hidden, false);
  assert.equal(page.elements.expiry.textContent, 'Session status unknown.');
  assert.match(page.elements.feedback.textContent, /may have ended/);
  await page.submit();
  assert.equal(page.requests.length, 0);
  assert.equal(page.elements.link.value, 'tt://?test');
});

test('returning from a short sleep resynchronizes with TV and keeps QR authorization', async () => {
  const page = openPage();
  page.sleepFor(60_000);
  await page.events.visibilitychange();
  assert.match(page.elements.expiry.textContent, /4:00/);
  assert.equal(page.elements.submit.disabled, false);
  assert.equal(page.elements.retry.hidden, true);
  assert.equal(page.checks[0].body, undefined, 'Status checks must not send credentials');
  page.elements.link.value = 'tt://?test';
  await page.submit();
  assert.deepEqual(page.requests, [{ token: 'test-qr-token', link: 'tt://?test' }]);
});

test('submission after sleep checks status before sending any configuration', async () => {
  const page = openPage();
  page.elements.link.value = 'tt://?test';
  page.sleepFor(360_000);
  await page.submit();
  await settle();
  assert.equal(page.checks.length, 1);
  assert.equal(page.requests.length, 0);
  assert.equal(page.elements.submit.disabled, true);
});

test('status timeout is retryable without losing the link or QR token', async () => {
  const page = openPage();
  page.elements.link.value = 'tt://?test';
  page.setStatusHandler(({ signal }) => new Promise((_, reject) => {
    signal.addEventListener('abort', () => reject(new Error('Timed out')));
  }));
  const firstCheck = page.events.visibilitychange();
  await page.events.visibilitychange();
  assert.equal(page.checks.length, 1, 'Concurrent checks must be coalesced');
  await page.timeoutChecks();
  await firstCheck;
  assert.equal(page.elements.submit.disabled, true);
  assert.equal(page.elements.retry.hidden, false);
  page.setStatusHandler(undefined);
  await page.events.click();
  assert.equal(page.elements.submit.disabled, false);
  assert.equal(page.elements.retry.hidden, true);
  await page.submit();
  assert.deepEqual(page.requests, [{ token: 'test-qr-token', link: 'tt://?test' }]);
});

test('a status response queued before sleep cannot revive a stale countdown', async () => {
  const page = openPage();
  let resolve;
  page.setStatusHandler(() => new Promise((accept) => { resolve = accept; }));
  const pending = page.events.visibilitychange();
  page.sleepFor(360_000);
  resolve(statusReply(300_000));
  await pending;
  assert.equal(page.elements.submit.disabled, true);
  assert.equal(page.elements.expiry.textContent, 'Session status unknown.');
  assert.equal(page.elements.retry.hidden, false);
});

test('a late status response cannot reopen a session that already expired', async () => {
  const page = openPage({ remaining: 1000 });
  let resolve;
  page.setStatusHandler(() => new Promise((accept) => { resolve = accept; }));
  const pending = page.events.visibilitychange();
  await page.advance(2000);
  resolve(statusReply(1000));
  await pending;
  assert.equal(page.elements.submit.disabled, true);
  assert.match(page.elements.feedback.textContent, /expired/);
  assert.equal(page.elements.retry.hidden, true);
});
