const { test, expect, openGame, createGame, snapshot } = require('./helpers.cjs');

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
  await page.getByLabel('player 2').selectOption({ label: 'ai' });
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
  await page.getByRole('button', { name: /^move \(m\)$/ }).click();
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
