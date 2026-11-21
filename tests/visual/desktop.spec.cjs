const { test, expect, openGame, createGame, snapshot } = require('./helpers.cjs');
const { checkUnloadedInfantry } = require('./unloaded-infantry.cjs');

test('home, about, and create-lobby form', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'create a lobby', exact: true })).toBeVisible();
  await snapshot(page, 'home');
  await page.getByRole('button', { name: 'about', exact: true }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await snapshot(page, 'about');
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await page.getByRole('button', { name: 'create a lobby', exact: true }).click();
  await expect(page.getByLabel('user name')).toBeVisible();
  await snapshot(page, 'create-lobby');
});

test('create a real lobby, choose a map, and start a game', async ({ page }) => {
  await page.goto('/new');
  await page.getByLabel('user name').fill('commander');
  await page.getByLabel('lobby name').fill('visual patrol');
  await page.getByRole('button', { name: 'create lobby', exact: true }).click();
  await expect(page).toHaveURL(/\/lobby\/[0-9a-f]+$/);
  await snapshot(page, 'lobby');
  await page.getByRole('button', { name: 'choose map', exact: true }).click();
  await expect(page.getByLabel('search maps')).toBeVisible();
  await snapshot(page, 'map-picker');
  await page.getByRole('button', { name: 'use this map', exact: true }).click();
  const opponent = page.getByLabel('player 2');
  await expect(opponent.locator('option')).toHaveText([
    'human', 'ai easy', 'ai medium', 'ai hard', 'ai very hard',
  ]);
  await opponent.selectOption({ label: 'ai easy' });
  await page.getByRole('button', { name: 'start game', exact: true }).click();
  await expect(page).toHaveURL(/\/game\/[0-9a-f]+$/);
  await expect(page.getByRole('group', { name: 'battlefield', exact: true })).toBeVisible();
  await snapshot(page, 'started-game');
});

test('battlefield, selected tank, orders, and settings', async ({ page }) => {
  await openGame(page);
  await snapshot(page, 'battlefield');
  await page.getByRole('button', { name: /tank 11$/ }).click();
  await snapshot(page, 'selected-tank');
  // Keep the pointer off the map when the order menu disappears.
  await page.getByRole('button', { name: /^move \(m\)$/ }).press('Enter');
  await snapshot(page, 'movement-planning');
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: 'menu', exact: true }).click();
  await page.getByRole('button', { name: 'settings', exact: true }).click();
  await expect(page.locator('#settings')).toBeVisible();
  await snapshot(page, 'settings-dialogs');
  await page.getByRole('tab', { name: 'audio', exact: true }).click();
  await snapshot(page, 'settings-audio');
  await page.keyboard.press('Escape');
  await expect(page.locator('#settings')).toHaveCount(0);

  const viewControls = page.getByRole('region', { name: 'view controls' });
  const overview = viewControls.getByText('100%', { exact: true }).filter({ visible: true });
  await viewControls.getByRole('button', { name: 'zoom in' }).click();
  await expect(overview).toHaveCount(0);
  await viewControls.getByRole('button', { name: 'reset view', exact: true }).press('Enter');
  await expect(overview).toBeVisible();

  const surrender = page.getByRole('button', { name: 'surrender', exact: true });
  await surrender.press('Enter');
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(surrender).toBeFocused();

  await page.getByRole('button', { name: 'menu', exact: true }).click();
  const openDevPanel = page.getByRole('button', { name: 'dev panel', exact: true });
  await openDevPanel.click();
  const devPanel = page.getByRole('dialog', { name: 'dev panel', exact: true });
  await expect(devPanel.getByRole('heading', { name: 'dev panel' })).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(devPanel).toHaveCount(0);
  await expect(openDevPanel).toBeVisible();
});

test('units without orders excludes units with a saved order', async ({ page }) => {
  await openGame(page);
  await page.getByRole('button', { name: /tank 11$/ }).click();
  await page.keyboard.press('h');
  await page.getByRole('button', { name: 'submit turn', exact: true }).click();

  const dialog = page.getByRole('dialog', { name: 'units without orders', exact: true });
  const units = dialog.getByRole('list', { name: 'units that will hold position' });
  await expect(units.getByRole('listitem').first()).toBeVisible();
  await expect(units.getByRole('listitem').filter({ hasText: /tank/ })).toHaveCount(0);
  await expect(dialog.getByRole('button', { name: 'submit anyway' })).toBeInViewport({ ratio: 1 });
  await dialog.getByRole('button', { name: 'keep planning' }).press('Enter');
  await expect(dialog).toHaveCount(0);
  await page.getByRole('button', { name: 'submit turn', exact: true }).click();
  await expect(dialog).toBeVisible();
});

test('a depot stock bar selects its square during movement planning', async ({ page }) => {
  await openGame(page);
  const battlefield = page.getByRole('group', { name: 'battlefield', exact: true });
  const stock = battlefield.getByRole('button', { name: /^supply depot · / }).first();
  const tank = battlefield.getByRole('button', { name: /tank 11$/ });
  const panel = page.getByRole('complementary', { name: 'game panel' });
  const supplyDepot = panel.getByRole('region', { name: 'supply depot', exact: true });

  await stock.click();
  await expect(supplyDepot).toBeVisible();

  await tank.click();
  await page.keyboard.press('m');
  await expect(battlefield.getByRole('button', { name: 'move to (2, 8)', exact: true })).toBeVisible();
  await stock.click();

  const saved = battlefield.locator('polyline[stroke-dasharray="2 1"]');
  await expect(saved).toHaveAttribute('points', / 40,136$/);

  await page.getByRole('button', { name: 'revoke order', exact: true }).click();
  await tank.click();
  await page.keyboard.press('a');
  await expect(battlefield.getByRole('button', { name: 'attack move to (2, 8)', exact: true })).toBeVisible();
  await stock.press('Enter');
  await expect(battlefield.getByLabel('choose attack move final direction')).toBeVisible();
});

test('first-game briefing and turn introduction', async ({ page }) => {
  const url = await createGame(page);
  await page.addInitScript(() => localStorage.setItem('fightlines.localStorage', JSON.stringify({
    audioMuted: true,
  })));
  await page.goto(url);
  await expect(page.locator('#welcome-briefing')).toBeVisible();
  await snapshot(page, 'welcome-briefing');
  await page.getByRole('button', { name: /got it/ }).click();
  await expect(page.locator('#turn-introduction')).toBeVisible();
  await snapshot(page, 'turn-introduction');
  await page.getByRole('button', { name: 'begin turn', exact: true }).click();
  await expect(page.locator('#turn-introduction')).toHaveCount(0);
});

test('placeholder flag leaves desktop battlefield unchanged', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('fightlines.localStorage', JSON.stringify({
    audioMuted: true, welcomeBriefingDismissed: true,
    skipTurnIntroduction: true, features: ['placeholder'],
  })));
  await openGame(page);
  await snapshot(page, 'battlefield');
});

test('the CRT battlefield flag affects only the board and persists', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await openGame(page);
  const viewport = page.getByLabel('battlefield navigation', { exact: true });
  const battlefield = page.getByRole('group', { name: 'battlefield', exact: true });
  const turnLabel = page.getByLabel('game header', { exact: true }).getByRole('status');
  const menuButton = page.getByRole('button', { name: 'menu', exact: true });
  const devPanel = page.getByRole('dialog', { name: 'dev panel', exact: true });
  const crtFlag = devPanel.getByRole('checkbox', { name: 'crt battlefield', exact: true });
  const crtBackground = () =>
    viewport.evaluate(element => getComputedStyle(element, '::after').backgroundImage);
  const openFeatures = async () => {
    await page.keyboard.press('Backquote');
    await devPanel.getByRole('tab', { name: 'features', exact: true }).click();
  };
  const closeFeatures = async () => {
    await devPanel.getByRole('button', { name: 'done', exact: true }).click();
    await expect(devPanel).toHaveCount(0);
  };

  await expect.poll(crtBackground).toBe('none');
  await expect(turnLabel).toHaveCSS('text-shadow', 'none');
  const bounds = await battlefield.boundingBox();
  await openFeatures();
  await expect(crtFlag).not.toBeChecked();
  await crtFlag.check();
  await expect.poll(crtBackground).toContain('repeating-linear-gradient');
  await closeFeatures();
  await expect(turnLabel).toHaveCSS('text-shadow', 'none');
  await expect(menuButton).toHaveCSS('text-shadow', 'none');
  expect(await viewport.evaluate(element => getComputedStyle(element, '::after').animationName)).toBe('none');
  expect(await battlefield.boundingBox()).toEqual(bounds);
  await battlefield.getByRole('button', { name: /tank 11$/ }).click();
  await expect(page.getByRole('button', { name: /^move \(m\)$/ })).toBeVisible();

  await page.reload();
  await expect.poll(crtBackground).toContain('repeating-linear-gradient');
  await page.setViewportSize({ width: 852, height: 393 });
  await expect(page.getByLabel('mobile battlefield', { exact: true })).toBeVisible();
  await expect.poll(crtBackground).toContain('repeating-linear-gradient');
  await expect(turnLabel).toHaveCSS('text-shadow', 'none');
  await expect(menuButton).toHaveCSS('text-shadow', 'none');

  await openFeatures();
  await expect(crtFlag).toBeChecked();
  await crtFlag.uncheck();
  await closeFeatures();
  await expect.poll(crtBackground).toBe('none');
});

test('board tilt changes the battlefield and persists across reload', async ({ page }) => {
  await openGame(page);
  const battlefield = page.getByRole('group', { name: 'battlefield', exact: true });
  const devPanel = page.getByRole('dialog', { name: 'dev panel', exact: true });
  const tilt = devPanel.getByRole('checkbox', { name: 'board tilt', exact: true });
  const transform = () => battlefield.evaluate(element => getComputedStyle(element.parentElement).transform);
  const openFeatures = async () => {
    await page.keyboard.press('Backquote');
    await devPanel.getByRole('tab', { name: 'features', exact: true }).click();
  };

  await expect.poll(transform).toBe('none');
  await openFeatures();
  await expect(tilt).not.toBeChecked();
  await tilt.check();
  await expect.poll(transform).toMatch(/^matrix3d\(/);
  await devPanel.getByRole('button', { name: 'done', exact: true }).click();

  const tank = battlefield.getByRole('button', { name: /tank 11$/ });
  const beforeZoom = await tank.boundingBox();
  const anchor = {
    x: beforeZoom.x + beforeZoom.width / 2,
    y: beforeZoom.y + beforeZoom.height / 2,
  };
  await page.mouse.move(anchor.x, anchor.y);
  await page.mouse.wheel(0, -100);
  await expect.poll(async () => (await tank.boundingBox()).width).toBeGreaterThan(beforeZoom.width);
  const afterZoom = await tank.boundingBox();
  expect(Math.abs(afterZoom.x + afterZoom.width / 2 - anchor.x)).toBeLessThan(1);
  expect(Math.abs(afterZoom.y + afterZoom.height / 2 - anchor.y)).toBeLessThan(1);

  await tank.click();
  const orders = page.getByRole('region', { name: 'unit orders', exact: true });
  await expect(orders).toBeVisible();
  expect((await orders.boundingBox()).x).toBeGreaterThan((await tank.boundingBox()).x);
  await orders.getByRole('button', { name: /^move \(m\)$/ }).click();
  await battlefield.getByRole('button', { name: 'move to (5, 8)', exact: true }).click();
  await expect(battlefield.locator('polyline[stroke-dasharray="2 1"]')).toHaveAttribute('points', '72,136 88,136');

  await page.reload();
  await expect.poll(transform).toMatch(/^matrix3d\(/);
  await openFeatures();
  await expect(tilt).toBeChecked();
  await tilt.uncheck();
  await expect.poll(transform).toBe('none');
});

test('order unloaded infantry, hold, and cancel the truck order', checkUnloadedInfantry);
