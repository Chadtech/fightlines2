const { test, expect, openGame, createGame, graphql, snapshot } = require('./helpers.cjs');

const interaction = { tag: '@mobile-interaction' };

test('game menu lets touch players switch mobile view on and off', interaction, async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => {
    const key = 'fightlines.localStorage';
    const preferences = JSON.parse(localStorage.getItem(key));
    localStorage.setItem(key, JSON.stringify({ ...preferences, features: [] }));
  });
  await openGame(page);

  const menu = page.getByRole('dialog', { name: 'menu', exact: true });
  const panel = page.getByRole('dialog', { name: 'dev panel', exact: true });
  const mobileView = panel.getByRole('checkbox', { name: 'mobile view', exact: true });
  const openPanel = menu.getByRole('button', { name: 'dev panel', exact: true });
  const done = panel.getByRole('button', { name: 'done', exact: true });
  const mobileBattlefield = page.locator('[aria-label="mobile battlefield"]');

  await expect(mobileBattlefield).toBeHidden();
  await page.getByRole('button', { name: 'menu', exact: true }).tap();
  await openPanel.tap();
  await expect(panel.getByRole('button', { name: 'close dev panel', exact: true })).toHaveCount(0);
  await panel.getByRole('tab', { name: 'features', exact: true }).tap();
  await expect(mobileView).not.toBeChecked();
  await mobileView.tap();
  await expect(mobileView).toBeChecked();
  await page.setViewportSize({ width: 667, height: 260 });
  await expect(done).toBeInViewport({ ratio: 1 });
  await done.tap();
  await expect(menu).toBeVisible();
  await expect(mobileBattlefield).toBeVisible();

  await openPanel.tap();
  await expect(mobileView).toBeChecked();
  await mobileView.tap();
  await expect(mobileView).not.toBeChecked();
  await done.tap();
  await expect(menu).toBeVisible();
  await expect(mobileBattlefield).toBeHidden();
});

async function swipeUp(page, scrollArea) {
  const bounds = await scrollArea.boundingBox();
  expect(bounds, 'visible scroll area').not.toBeNull();
  const x = bounds.x + bounds.width * 0.75;
  const y = bounds.y + bounds.height * 0.8;
  const distance = bounds.height * 0.6;
  // Send a browser touch gesture so hit testing and native scrolling both run.
  const session = await page.context().newCDPSession(page);
  try {
    await session.send('Input.dispatchTouchEvent', {
      type: 'touchStart', touchPoints: [{ x, y }],
    });
    for (const fraction of [0.25, 0.5, 0.75, 1]) {
      await session.send('Input.dispatchTouchEvent', {
        type: 'touchMove', touchPoints: [{ x, y: y - distance * fraction }],
      });
    }
    await session.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  } finally {
    await session.detach();
  }
}

test('home keeps all menu actions visible in short landscape', interaction, async ({ page }) => {
  await page.goto('/');
  const logo = page.getByRole('heading', { name: 'fightlines', exact: true });
  const menu = page.getByRole('navigation', { name: 'main navigation' });
  const about = menu.getByRole('button', { name: 'about', exact: true });

  for (const viewport of [page.viewportSize(), { width: 667, height: 260 }]) {
    await page.setViewportSize(viewport);
    await expect(logo).toBeInViewport({ ratio: 1 });
    await expect(menu).toBeInViewport({ ratio: 1 });
    await expect(page.locator('blockquote')).toBeInViewport({ ratio: 1 });
    const logoBounds = await logo.boundingBox();
    const menuBounds = await menu.boundingBox();
    expect(menuBounds.x).toBeGreaterThan(logoBounds.x + logoBounds.width);
  }

  await page.setViewportSize({ width: 852, height: 393 });
  await about.tap();
  const dialog = page.getByRole('dialog', { name: 'about fightlines', exact: true });
  await dialog.getByRole('button', { name: 'close', exact: true }).tap();
  await expect(about).toBeFocused();
});

test('short landscape lobby keeps setup, chat, and map selection reachable', interaction, async ({ page }) => {
  const { createLobby } = await graphql(page,
    'mutation { createLobby(name: "commander", lobbyName: "landscape patrol") { id } }');
  await page.goto(`/lobby/${createLobby.id}`);
  const chooseMap = page.getByRole('button', { name: 'choose map', exact: true });
  const start = page.getByRole('button', { name: /^start game/ });
  const chat = page.getByRole('textbox', { name: 'chat message' });
  const playersTab = page.getByRole('tab', { name: 'players', exact: true });
  const chatTab = page.getByRole('tab', { name: 'chat', exact: true });
  const send = page.getByRole('button', { name: 'send', exact: true });

  await expect(playersTab).toHaveAttribute('aria-selected', 'true');
  await expect(chat).toBeHidden();
  await playersTab.focus();
  await page.keyboard.press('ArrowRight');
  await expect(chatTab).toBeFocused();
  await expect(chatTab).toHaveAttribute('aria-selected', 'true');
  await page.keyboard.press('ArrowLeft');
  await expect(playersTab).toBeFocused();

  for (const viewport of [{ width: 852, height: 393 }, { width: 667, height: 260 }]) {
    await page.setViewportSize(viewport);
    await expect(start).toBeInViewport({ ratio: 1 });
    await chooseMap.tap();
    await page.getByLabel('search maps').fill('visual');
    await page.getByRole('button', { name: 'preview visual battlefield', exact: true }).tap();
    const useMap = page.getByRole('button', { name: 'use this map', exact: true });
    await expect(useMap).toBeInViewport({ ratio: 1 });
    await useMap.tap();
    await expect(chooseMap).toBeVisible();
    await page.keyboard.press('c');
    await expect(chatTab).toHaveAttribute('aria-selected', 'true');
    await expect(chat).toBeFocused();
    await expect(chat).toBeInViewport({ ratio: 1 });
    await expect(send).toBeInViewport({ ratio: 1 });
    await expect(start).toBeInViewport({ ratio: 1 });
    await chat.fill(`hello from ${viewport.width}`);
    await send.tap();
    await expect(page.getByRole('paragraph').filter({
      hasText: `commander: hello from ${viewport.width}`,
    })).toBeInViewport();
    await playersTab.tap();
    await expect(chat).toBeHidden();
  }

  const playersPanel = page.getByRole('tabpanel', { name: 'players', exact: true });
  const playerSettings = playersPanel.locator(':scope > div');
  const tabBar = page.getByRole('tablist', { name: 'lobby' });
  await expect(playersPanel.getByRole('heading', { name: 'players', exact: true })).toHaveCount(0);
  const tabBarBounds = await tabBar.boundingBox();
  await swipeUp(page, playerSettings);
  await expect.poll(() => playerSettings.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
  expect(await tabBar.boundingBox()).toEqual(tabBarBounds);

  await page.getByLabel('player 2').selectOption({ label: 'ai' });
  await start.tap();
  await expect(page).toHaveURL(/\/game\/[0-9a-f]+$/);
});

test('short landscape chat marks incoming messages until opened', interaction, async ({ page, browser, baseURL }) => {
  const { createLobby } = await graphql(page,
    'mutation { createLobby(name: "commander", lobbyName: "chat patrol") { id } }');
  const id = JSON.stringify(createLobby.id);
  await page.goto(`/lobby/${createLobby.id}`);
  const chatTab = page.getByRole('tab', { name: /^chat/ });
  await expect(chatTab).toHaveAccessibleName('chat');

  const peer = await browser.newContext({ baseURL });
  try {
    const peerPage = await peer.newPage();
    await graphql(peerPage, `mutation { joinLobby(id: ${id}, name: "scout") { id } }`);
    await graphql(peerPage, `mutation {
      sendChat(input: { id: ${id}, messageId: "landscape-chat-1", text: "ready to play" }) { sequence }
    }`);
    await expect(chatTab).toHaveAccessibleName('chat, unread messages');
    await expect(chatTab).toHaveText('chat •');
    await chatTab.tap();
    await expect(chatTab).toHaveAccessibleName('chat');
    await expect(page.getByText('scout: ready to play')).toBeInViewport();
  } finally {
    await peer.close();
  }
});

test('battlefield', async ({ page }) => {
  await openGame(page);
  await snapshot(page, 'battlefield');
});

test('orders rail', async ({ page }) => {
  await openGame(page);
  await page.getByRole('button', { name: /tank 11$/ }).click();
  const orders = page.getByRole('region', { name: 'unit orders', exact: true });
  await expect(orders.getByRole('button', { name: 'move', exact: true })).toBeVisible();
  await expect(orders.locator('[aria-keyshortcuts]')).toHaveCount(0);
  await snapshot(page, 'orders-rail');
  await page.setViewportSize({ width: 667, height: 260 });
  const panel = page.getByRole('complementary', { name: 'selection panel' });
  const scrollArea = panel.locator(':scope > div').filter({ has: orders });
  await swipeUp(page, scrollArea);
  await expect.poll(() => scrollArea.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
});

for (const order of ['move', 'attack move']) {
  test(`touch drag traces and confirms ${order}`, interaction, async ({ page }) => {
    await openGame(page);
    const battlefield = page.getByRole('group', { name: 'battlefield', exact: true });
    const tank = battlefield.getByRole('button', { name: /tank 11$/ });
    const dimmedSprite = tank.locator('..').locator(':scope > g[filter="url(#battlefield-ordered-unit)"]');
    await expect(dimmedSprite).toHaveCount(0);
    await tank.tap();
    const orders = page.getByRole('region', { name: 'unit orders', exact: true });
    await orders.getByRole('button', { name: order, exact: true }).tap();
    await expect(page.getByText('drag to trace a route, or tap a destination.')).toBeVisible();

    const bounds = await battlefield.boundingBox();
    const tile = (x, y) => ({
      x: bounds.x + (x + 0.5) * bounds.width / 17,
      y: bounds.y + (y + 0.5) * bounds.height / 17,
    });
    const origin = tile(4, 8);
    const destination = tile(5, 8);
    // The direct route would skip both waypoints. Trace around the corner instead.
    const points = '72,136 72,120 88,120 88,136';
    const preview = battlefield.locator('polyline[stroke-width="1.5"]');
    const saved = battlefield.locator('polyline[stroke-dasharray="2 1"]');
    const session = await page.context().newCDPSession(page);
    const touch = (type, touchPoints = []) =>
      session.send('Input.dispatchTouchEvent', { type, touchPoints });

    try {
      await touch('touchStart', [origin]);
      await touch('touchMove', [tile(4, 9)]);
      await expect(preview).toHaveAttribute('points', '72,136 72,152');
      await touch('touchCancel');
      await expect(saved).toHaveCount(0);

      await touch('touchStart', [origin]);
      await touch('touchMove', [tile(4, 7)]);
      await touch('touchMove', [tile(5, 7)]);
      await touch('touchMove', [destination]);
      await expect(preview).toHaveAttribute('points', points);
      expect(await battlefield.boundingBox()).toEqual(bounds);
      await touch('touchEnd');
    } finally {
      await session.detach();
    }

    if (order === 'attack move') {
      const facing = battlefield.getByLabel('choose attack move final direction');
      await expect(facing).toBeVisible();
      await expect(preview).toHaveAttribute('points', points);
      await facing.getByRole('button', { name: 'face east', exact: true }).tap();
    }
    await expect(saved).toHaveAttribute('points', points);
    await expect(dimmedSprite).toHaveCount(1);
    await page.getByRole('button', { name: 'revoke order', exact: true }).tap();
    await expect(saved).toHaveCount(0);
    await expect(dimmedSprite).toHaveCount(0);
  });
}

test('details rail', async ({ page }) => {
  await openMobileDetails(page);
  await snapshot(page, 'details-rail');
  const terrain = page.getByRole('region', { name: 'terrain', exact: true });
  await expect(terrain.getByRole('img')).toHaveCount(0);
  const aboutTerrain = terrain.getByRole('button', { name: /^about terrain:/ });
  await aboutTerrain.tap();
  const dialog = page.getByRole('dialog', { name: /^about terrain:/ });
  const close = dialog.getByRole('button', { name: 'close', exact: true });
  await expect(dialog.getByRole('button')).toHaveCount(1);
  await expect(close).toBeInViewport({ ratio: 1 });
  const bottomGap = await close.evaluate(button =>
    button.closest('dialog').getBoundingClientRect().bottom - button.getBoundingClientRect().bottom
  );
  expect(bottomGap).toBeLessThan(24);
  await close.tap();
  await expect(dialog).toHaveCount(0);
  await expect(aboutTerrain).toBeFocused();
});

test('about unit keeps the title and close button visible while content scrolls', async ({ page }) => {
  await openMobileDetails(page);
  await page.setViewportSize({ width: 667, height: 260 });
  const about = page.getByRole('button', { name: 'about tank', exact: true });
  await about.tap();

  const dialog = page.getByRole('dialog', { name: 'about tank', exact: true });
  const title = dialog.getByText('about tank', { exact: true });
  const close = dialog.getByRole('button', { name: 'close', exact: true });
  await expect(dialog.getByRole('button')).toHaveCount(1);
  await expect(dialog.locator('svg image')).toBeVisible();
  await expect(close).toBeInViewport({ ratio: 1 });
  const titleBounds = await title.boundingBox();
  const closeBounds = await close.boundingBox();
  const rows = dialog.getByRole('table', { name: 'unit statistics' }).getByRole('row');
  await expect(rows.last()).not.toBeInViewport();
  const scrollArea = dialog.getByRole('table').locator('xpath=ancestor::div[3]');
  await swipeUp(page, scrollArea);
  await expect.poll(() => scrollArea.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
  expect(await title.boundingBox()).toEqual(titleBounds);
  expect(await close.boundingBox()).toEqual(closeBounds);

  await close.tap();
  await expect(dialog).toHaveCount(0);
  await expect(about).toBeFocused();
});

test('tap a depot or empty tile to inspect it', async ({ page }) => {
  await openGame(page);
  const battlefield = page.getByRole('group', { name: 'battlefield', exact: true });
  const panel = page.getByRole('complementary', { name: 'selection panel' });
  const details = panel.getByRole('tab', { name: 'details', exact: true });
  const depot = battlefield.getByRole('button', { name: /^(supply|fuel) depot$/ }).first();
  const close = panel.getByRole('button', { name: 'close', exact: true });
  await expect(panel).toHaveCount(0);

  await depot.tap();
  await expect(details).toHaveAttribute('aria-selected', 'true');
  const depotDetails = panel.getByRole('region', { name: /^(supply|fuel) depot$/ });
  await expect(depotDetails).toBeVisible();
  await expect(depotDetails.getByRole('img')).toHaveCount(0);
  await close.tap();
  await expect(panel).toHaveCount(0);

  const emptyTile = await battlefield.locator('rect[fill="transparent"][stroke-width="0.25"]').evaluateAll(tiles => {
    for (const tile of tiles) {
      const bounds = tile.getBoundingClientRect();
      const x = bounds.x + bounds.width / 2;
      const y = bounds.y + bounds.height / 2;
      if (document.elementFromPoint(x, y) === tile) return { x, y };
    }
    return null;
  });
  expect(emptyTile, 'an unobstructed terrain tile').not.toBeNull();
  await page.touchscreen.tap(emptyTile.x, emptyTile.y);
  await expect(details).toHaveAttribute('aria-selected', 'true');
  await expect(panel.getByRole('region', { name: 'terrain', exact: true })).toBeVisible();
  await expect(panel.getByRole('tab', { name: 'orders', exact: true })).toHaveCount(0);
  await close.tap();
  await expect(panel).toHaveCount(0);
});

test('settings', async ({ page }) => {
  await openMobileDetails(page);
  await page.getByRole('button', { name: 'menu', exact: true }).click();
  await page.getByRole('button', { name: 'settings', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'settings', exact: true });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole('button', { name: 'close settings', exact: true })).toHaveCount(0);
  await snapshot(page, 'settings');

  await page.setViewportSize({ width: 667, height: 260 });
  const done = dialog.getByRole('button', { name: 'done', exact: true });
  const tabs = dialog.getByRole('tablist');
  await expect(done).toBeInViewport({ ratio: 1 });
  await expect(tabs).toBeInViewport({ ratio: 1 });
  const doneBeforeScroll = await done.boundingBox();
  const tabsBeforeScroll = await tabs.boundingBox();

  for (const name of ['dialogs', 'audio']) {
    await tabs.getByRole('tab', { name, exact: true }).click();
    const pane = dialog.getByRole('tabpanel', { name, exact: true });
    const scrollArea = pane.locator(':scope > div');
    const scrollBounds = await scrollArea.boundingBox();
    expect(scrollBounds.y).toBe(tabsBeforeScroll.y);
    expect(scrollBounds.y + scrollBounds.height).toBe(doneBeforeScroll.y + doneBeforeScroll.height);
    expect(scrollBounds.x).toBeGreaterThan(doneBeforeScroll.x + doneBeforeScroll.width);
    await swipeUp(page, scrollArea);
    await expect.poll(() => scrollArea.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
    expect(await done.boundingBox()).toEqual(doneBeforeScroll);
    expect(await tabs.boundingBox()).toEqual(tabsBeforeScroll);
  }

  await done.click();
  await expect(dialog).toHaveCount(0);
});

test('units without orders scroll above the submission actions', interaction, async ({ page }) => {
  await page.setViewportSize({ width: 667, height: 260 });
  await openGame(page);
  await page.getByRole('button', { name: 'submit turn', exact: true }).tap();

  const dialog = page.getByRole('dialog', { name: 'units without orders', exact: true });
  const units = dialog.getByRole('list', { name: 'units that will hold position' });
  const keepPlanning = dialog.getByRole('button', { name: 'keep planning', exact: true });
  await expect(units.getByRole('listitem')).toHaveText([
    'infantry', 'infantry', 'infantry', 'truck', 'truck', 'tank', 'field gun', 'field gun',
  ]);
  await expect(keepPlanning).toBeInViewport({ ratio: 1 });
  await expect(dialog.getByRole('button', { name: 'submit anyway' })).toBeInViewport({ ratio: 1 });
  await expect(dialog.getByRole('checkbox', { name: 'skip this dialog' })).toBeInViewport({ ratio: 1 });
  const actionsBeforeScroll = await keepPlanning.boundingBox();
  expect(page.viewportSize().height - actionsBeforeScroll.y - actionsBeforeScroll.height).toBeLessThanOrEqual(16);

  await swipeUp(page, units);
  await expect.poll(() => units.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
  expect(await keepPlanning.boundingBox()).toEqual(actionsBeforeScroll);

  await keepPlanning.tap();
  await expect(dialog).toHaveCount(0);
});

test('resolved turn report on a short screen', async ({ page }) => {
  const dialog = await openResolvedTurnReport(page);
  await expectReportFits(page, dialog, { width: 852, height: 393 });
  await expectReportFits(page, dialog, { width: 667, height: 320 });
  await snapshot(page, 'resolved-turn-report');
  await dialog.getByRole('button', { name: 'begin turn', exact: true }).click();
  await expect(dialog).toHaveCount(0);
});

test('resolved turn report with spare height', async ({ page }) => {
  const dialog = await openResolvedTurnReport(page);
  await expectReportFits(page, dialog, { width: 828, height: 379 });
  await snapshot(page, 'resolved-turn-report-roomy');
});

test('game over opens with the result, report, and actions visible in landscape', interaction, async ({ page }) => {
  await openResolvedTurnReport(page);
  const id = JSON.stringify(page.url().split('/').pop());
  await graphql(page, `mutation { resignGame(id: ${id}) { id } }`);
  await page.setViewportSize({ width: 667, height: 260 });
  await page.reload();

  const dialog = page.getByRole('dialog', { name: 'game over', exact: true });
  const result = dialog.getByRole('heading', { name: / wins$/ });
  const report = dialog.getByRole('region', { name: 'previous turn report' });
  const feedback = dialog.getByRole('button', { name: 'give feedback', exact: true });
  const returnButton = dialog.getByRole('button', { name: 'return to battlefield', exact: true });
  await expect(result).toBeFocused();
  await expect.poll(() => dialog.locator(':scope > div').nth(1).evaluate(body =>
    body.scrollHeight - body.clientHeight
  )).toBeLessThanOrEqual(1);
  await expect(result).toBeInViewport({ ratio: 1 });
  await expect(report).toBeInViewport({ ratio: 1 });
  await expect(feedback).toBeInViewport({ ratio: 1 });
  await expect(returnButton).toBeInViewport({ ratio: 1 });
  expect((await report.boundingBox()).x).toBeLessThan((await returnButton.boundingBox()).x);

  await feedback.tap();
  const feedbackDialog = page.getByRole('dialog', { name: 'feedback', exact: true });
  await feedbackDialog.getByRole('button', { name: 'close', exact: true }).tap();
  await expect(feedback).toBeFocused();
  await returnButton.tap();
  await expect(dialog).toHaveCount(0);
});

async function openMobileDetails(page) {
  await openGame(page);
  await page.getByRole('button', { name: /tank 11$/ }).click();
  await page.getByRole('tab', { name: 'details', exact: true }).click();
}

async function openResolvedTurnReport(page) {
  const url = await createGame(page);
  await page.addInitScript(() => localStorage.setItem('fightlines.localStorage', JSON.stringify({
    audioMuted: true, welcomeBriefingDismissed: true,
    skipTurnIntroduction: false, features: ['mobileLandscape'],
  })));
  await page.goto(url);
  await page.getByRole('button', { name: 'begin turn', exact: true }).click();
  await page.getByRole('button', { name: 'submit turn', exact: true }).click();
  await page.getByRole('button', { name: 'submit anyway', exact: true }).click();
  const id = JSON.stringify(url.split('/').pop());
  await expect.poll(async () => {
    const { game } = await graphql(page, `{ game(id: ${id}) { turnNumber } }`);
    return game.turnNumber;
  }).toBe(2);
  // Reload exercises the normal introduction with its retained previous-turn report.
  await page.reload();
  const dialog = page.getByRole('dialog', { name: 'turn 2', exact: true });
  await expect(dialog).toBeVisible();
  await expect(dialog.locator('dd')).toHaveCount(4);
  return dialog;
}

async function expectReportFits(page, dialog, { width, height }) {
  await page.setViewportSize({ width, height });
  await expect.poll(() => dialog.evaluate(element => {
    const body = element.querySelector('form').parentElement;
    return body.scrollHeight - body.clientHeight;
  }), { message: `Turn report must fit without vertical scrolling at ${width}x${height}` }).toBeLessThanOrEqual(1);
  await expect.poll(() => dialog.evaluate(element => {
    const body = element.querySelector('form').parentElement;
    const actions = body.querySelector('form');
    return body.getBoundingClientRect().bottom - actions.getBoundingClientRect().bottom;
  }), { message: `Actions must sit at the bottom at ${width}x${height}` }).toBeLessThanOrEqual(16);
  for (const metric of await dialog.locator('dt, dd').all()) {
    await expect(metric).toBeInViewport({ ratio: 1 });
  }
  await expect(dialog.getByRole('button', { name: 'begin turn', exact: true })).toBeInViewport({ ratio: 1 });
  await expect(dialog.getByRole('button', { name: 'replay turn', exact: true })).toBeInViewport({ ratio: 1 });
  await expect(dialog.getByRole('checkbox', { name: 'skip this dialog', exact: true })).toBeInViewport({ ratio: 1 });
}
