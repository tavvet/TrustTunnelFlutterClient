String localImportPage({required String nonce, required Duration remaining}) =>
    '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="referrer" content="no-referrer">
  <title>TrustTunnel — Send server to TV</title>
  <style nonce="$nonce">
    :root { color-scheme: light; font-family: system-ui, sans-serif; color: #333e4c; background: #f6f7f9; }
    * { box-sizing: border-box; }
    body { margin: 0; padding: 32px 16px; }
    main { max-width: 560px; margin: 4vh auto; background: white; border-radius: 20px; padding: 32px; box-shadow: 0 8px 32px #333e4c0a; }
    .brand { color: #3972aa; font-size: 18px; font-weight: 750; }
    h1 { font-size: 28px; line-height: 1.2; margin: 24px 0 12px; }
    p { line-height: 1.5; }
    label { display: block; font-weight: 600; margin: 24px 0 8px; }
    input, textarea, button { width: 100%; font: inherit; border-radius: 8px; }
    input, textarea { border: 1px solid #9aa8b8; padding: 12px; background: white; color: #333e4c; }
    input { letter-spacing: .2em; }
    textarea { min-height: 150px; resize: vertical; overflow-wrap: anywhere; }
    :focus-visible { outline: 3px solid #3972aa; outline-offset: 3px; }
    button { border: 0; padding: 14px; background: #3972aa; color: white; margin-top: 24px; cursor: pointer; font-weight: 650; }
    button:disabled { opacity: .55; cursor: default; }
    .note { color: #5c6e84; font-size: 14px; }
    #feedback { min-height: 24px; font-weight: 550; }
    [hidden] { display: none !important; }
    @media (max-width: 420px) { main { padding: 24px; margin-top: 0; } h1 { font-size: 25px; } }
  </style>
</head>
<body>
  <main>
    <div class="brand">TrustTunnel</div>
    <h1>Send a server to your TV</h1>
    <p>Paste the TrustTunnel link from your server configuration. You can review the details on your TV before adding it.</p>
    <form id="import-form" autocomplete="off">
      <div id="code-group">
        <label for="code">Pairing code shown on TV</label>
        <input id="code" type="text" inputmode="numeric" pattern="[0-9]{6}" minlength="6" maxlength="6" autocomplete="off" placeholder="000000" required>
      </div>
      <label for="link">TrustTunnel link</label>
      <textarea id="link" placeholder="tt://?…" maxlength="16384" spellcheck="false" autocapitalize="off" autocomplete="off" required></textarea>
      <button id="submit" type="submit">Send to TV</button>
    </form>
    <button id="retry" type="button" hidden>Check connection again</button>
    <p id="feedback" role="status" aria-live="polite"></p>
    <p class="note" id="expiry"></p>
    <p class="note">The link is sent directly to your TV over your local network. This HTTP connection is not encrypted; use a trusted network.</p>
  </main>
  <script nonce="$nonce">
    (() => {
      'use strict';
      let token = new URLSearchParams(location.hash.slice(1)).get('token');
      history.replaceState(null, '', location.pathname);
      const form = document.getElementById('import-form');
      const codeGroup = document.getElementById('code-group');
      const code = document.getElementById('code');
      const link = document.getElementById('link');
      const button = document.getElementById('submit');
      const retry = document.getElementById('retry');
      const feedback = document.getElementById('feedback');
      const expiry = document.getElementById('expiry');
      // Use the TV's remaining duration, independent of this device's clock.
      let expiresAt = performance.now() + ${remaining.inMilliseconds};
      let lastTick = performance.now();
      let lastWallTime = Date.now();
      let finished = false;
      let busy = false;
      let needsCheck = false;
      let checking = false;
      if (token) {
        codeGroup.hidden = true;
        code.required = false;
      }
      const endSession = (message) => {
        finished = true;
        token = null;
        button.disabled = true;
        retry.hidden = true;
        expiry.textContent = 'This session has ended.';
        feedback.textContent = message;
        clearInterval(clock);
      };
      const renderTime = () => {
        if (finished || needsCheck) return;
        const seconds = Math.max(0, Math.ceil((expiresAt - performance.now()) / 1000));
        expiry.textContent = 'Session expires in ' + Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0') + '.';
        if (seconds === 0) {
          endSession('This session has expired. Open a new import session on your TV.');
        }
      };
      const checkSession = async () => {
        if (finished) return;
        if (performance.now() >= expiresAt) {
          endSession('This session has expired. Open a new import session on your TV.');
          return;
        }
        needsCheck = true;
        button.disabled = true;
        expiry.textContent = 'Checking session…';
        if (checking || busy) return;
        checking = true;
        retry.hidden = true;
        feedback.textContent = '';
        const controller = new AbortController();
        const requestedAt = performance.now();
        const requestedWallTime = Date.now();
        const timeout = setTimeout(() => controller.abort(), 5000);
        try {
          const response = await fetch('/status', {
            credentials: 'omit', cache: 'no-store', referrerPolicy: 'no-referrer', signal: controller.signal
          });
          if (finished) return;
          if (response.status === 410) {
            endSession('This session has expired. Open a new import session on your TV.');
            return;
          }
          if (!response.ok) throw new Error('Session unavailable');
          const result = await response.json();
          if (finished) return;
          const elapsed = performance.now() - requestedAt;
          if (elapsed >= 5000 || Math.abs((Date.now() - requestedWallTime) - elapsed) > 2000) {
            throw new Error('Stale session status');
          }
          if (!Number.isSafeInteger(result.remainingMilliseconds) || result.remainingMilliseconds < 0) {
            throw new Error('Invalid session status');
          }
          lastTick = performance.now();
          lastWallTime = Date.now();
          expiresAt = lastTick + Math.max(0, result.remainingMilliseconds - elapsed);
          needsCheck = false;
          renderTime();
        } catch (_) {
          if (finished) return;
          expiry.textContent = 'Session status unknown.';
          feedback.textContent = 'The session may have ended or your TV is unavailable. Check the import screen on your TV and try again.';
          retry.hidden = false;
        } finally {
          clearTimeout(timeout);
          checking = false;
          button.disabled = finished || needsCheck || busy;
        }
      };
      const updateTime = () => {
        if (finished) return;
        const tick = performance.now();
        const wallTime = Date.now();
        // Some browsers stop their monotonic clock during sleep. Wall-clock
        // jumps also trigger a check; only the TV decides how much time remains.
        const drift = Math.abs((wallTime - lastWallTime) - (tick - lastTick));
        lastTick = tick;
        lastWallTime = wallTime;
        if (tick >= expiresAt) {
          endSession('This session has expired. Open a new import session on your TV.');
          return;
        }
        if (drift > 2000 && !needsCheck) void checkSession();
        renderTime();
      };
      const clock = setInterval(updateTime, 1000);
      updateTime();
      retry.addEventListener('click', checkSession);
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') return checkSession();
      });
      form.addEventListener('submit', async (event) => {
        event.preventDefault();
        updateTime();
        if (finished || busy || needsCheck || !form.reportValidity()) return;
        const value = link.value.trim();
        if (!value.startsWith('tt://?')) {
          feedback.textContent = 'Paste a TrustTunnel link beginning with tt://?.';
          return;
        }
        busy = true;
        button.disabled = true;
        feedback.textContent = 'Sending…';
        try {
          const credentials = token ? { token } : { code: code.value.trim() };
          const response = await fetch('/import', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'omit',
            cache: 'no-store',
            referrerPolicy: 'no-referrer',
            body: JSON.stringify({ ...credentials, link: value })
          });
          const result = await response.json();
          feedback.textContent = result.message;
          if (response.ok && result.ok) {
            finished = true;
            token = null;
            link.value = '';
            code.value = '';
            form.hidden = true;
            retry.hidden = true;
            expiry.textContent = 'This session is now closed.';
            clearInterval(clock);
          } else if (response.status === 429 || response.status === 410) {
            endSession(result.message);
          }
        } catch (_) {
          feedback.textContent = 'Could not reach your TV. Check that the import screen is still open and both devices are on the same network.';
        } finally {
          busy = false;
          button.disabled = finished || needsCheck;
          if (!finished && needsCheck) void checkSession();
        }
      });
      window.addEventListener('pagehide', () => {
        token = null;
        link.value = '';
        code.value = '';
      });
      window.addEventListener('pageshow', (event) => {
        if (!event.persisted || finished) return;
        // A history restore keeps the DOM, but pagehide cleared the QR token.
        if (!token) {
          codeGroup.hidden = false;
          code.required = true;
        }
        return checkSession();
      });
    })();
  </script>
</body>
</html>
''';
