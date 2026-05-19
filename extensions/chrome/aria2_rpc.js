/** Shared JSON-RPC helpers for aria2down browser extensions. */
async function aria2LoadConfig(storageApi) {
  const data = await storageApi.sync.get(['rpcUrl', 'secret']);
  return {
    rpcUrl: (data.rpcUrl || 'http://127.0.0.1:6800/jsonrpc').trim(),
    secret: (data.secret || '').trim(),
  };
}

async function aria2AddUri(url, storageApi) {
  const { rpcUrl, secret } = await aria2LoadConfig(storageApi);
  const params = secret ? [secret, [url]] : [[url]];
  const res = await fetch(rpcUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: 'aria2down-ext',
      method: 'aria2.addUri',
      params,
    }),
  });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  const json = await res.json();
  if (json.error) {
    throw new Error(json.error.message || JSON.stringify(json.error));
  }
  return json.result;
}

async function aria2GetVersion(storageApi) {
  const { rpcUrl, secret } = await aria2LoadConfig(storageApi);
  const params = secret ? [secret] : [];
  const res = await fetch(rpcUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: 'aria2down-ext',
      method: 'aria2.getVersion',
      params,
    }),
  });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  const json = await res.json();
  if (json.error) {
    throw new Error(json.error.message || JSON.stringify(json.error));
  }
  return json.result;
}
