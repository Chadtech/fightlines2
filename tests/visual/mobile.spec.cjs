const { test, expect, openGame, createGame, graphql, snapshot } = require('./helpers.cjs');

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
