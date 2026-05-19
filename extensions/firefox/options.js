const rpcUrlEl = document.getElementById('rpcUrl');
const secretEl = document.getElementById('secret');
const statusEl = document.getElementById('status');

function applyConfig(obj) {
  if (obj.rpcUrl) rpcUrlEl.value = String(obj.rpcUrl).trim();
  if (obj.secret != null) secretEl.value = String(obj.secret).trim();
}

const storage = typeof browser !== 'undefined' ? browser.storage : chrome.storage;

document.getElementById('test').addEventListener('click', async () => {
  statusEl.textContent = 'Testing…';
  try {
    const v = await aria2GetVersion(storage);
    statusEl.textContent = `OK — aria2 ${v.version ?? '?'}`;
  } catch (e) {
    statusEl.textContent = `Failed: ${e}`;
  }
});

document.getElementById('save').addEventListener('click', async () => {
  await storage.sync.set({
    rpcUrl: rpcUrlEl.value.trim() || 'http://127.0.0.1:6800/jsonrpc',
    secret: secretEl.value.trim(),
  });
  statusEl.textContent = 'Saved.';
});

document.getElementById('importConfig').addEventListener('click', async () => {
  try {
    const text = await navigator.clipboard.readText();
    const obj = JSON.parse(text);
    if (!obj.rpcUrl) {
      statusEl.textContent = 'Clipboard JSON must include rpcUrl.';
      return;
    }
    applyConfig(obj);
    await storage.sync.set({
      rpcUrl: rpcUrlEl.value.trim(),
      secret: secretEl.value.trim(),
    });
    statusEl.textContent = 'Imported from clipboard.';
  } catch (e) {
    statusEl.textContent = `Import failed: ${e}`;
  }
});

storage.sync.get(['rpcUrl', 'secret'], (data) => {
  rpcUrlEl.value = data.rpcUrl || 'http://127.0.0.1:6800/jsonrpc';
  secretEl.value = data.secret || '';
});
