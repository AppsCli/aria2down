/* global browser, aria2AddUri */
const api = typeof browser !== 'undefined' ? browser : chrome;
const MENU_ID = 'aria2down-add-link';

const PAGE_MENU_ID = 'aria2down-add-page';

api.runtime.onInstalled.addListener(() => {
  api.contextMenus.create({
    id: MENU_ID,
    title: 'Send link to aria2 (aria2down)',
    contexts: ['link'],
  });
  api.contextMenus.create({
    id: PAGE_MENU_ID,
    title: 'Send this page to aria2 (aria2down)',
    contexts: ['page'],
  });
});

api.contextMenus.onClicked.addListener(async (info) => {
  const url =
    info.menuItemId === PAGE_MENU_ID ? info.pageUrl : info.linkUrl;
  if ((info.menuItemId !== MENU_ID && info.menuItemId !== PAGE_MENU_ID) || !url) {
    return;
  }
  try {
    const gid = await aria2AddUri(url, api.storage);
    console.log('[aria2down] added', url, gid);
  } catch (e) {
    console.error('[aria2down]', e);
  }
});
