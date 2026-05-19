// P5-08：通过 JSON-RPC 将链接发送到本机 aria2。
importScripts('aria2_rpc.js');

const MENU_ID = 'aria2down-add-link';

const PAGE_MENU_ID = 'aria2down-add-page';

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: MENU_ID,
    title: 'Send link to aria2 (aria2down)',
    contexts: ['link'],
  });
  chrome.contextMenus.create({
    id: PAGE_MENU_ID,
    title: 'Send this page to aria2 (aria2down)',
    contexts: ['page'],
  });
});

function flashBadge(ok) {
  chrome.action.setBadgeBackgroundColor({ color: ok ? '#2e7d32' : '#c62828' });
  chrome.action.setBadgeText({ text: ok ? 'OK' : '!' });
  setTimeout(() => chrome.action.setBadgeText({ text: '' }), 2500);
}

chrome.contextMenus.onClicked.addListener(async (info) => {
  const url =
    info.menuItemId === PAGE_MENU_ID ? info.pageUrl : info.linkUrl;
  if ((info.menuItemId !== MENU_ID && info.menuItemId !== PAGE_MENU_ID) || !url) {
    return;
  }
  try {
    const gid = await aria2AddUri(url, chrome.storage);
    console.log('[aria2down] added', url, gid);
    flashBadge(true);
  } catch (e) {
    console.error('[aria2down]', e);
    flashBadge(false);
  }
});

chrome.action.onClicked.addListener(() => {
  chrome.runtime.openOptionsPage();
});
