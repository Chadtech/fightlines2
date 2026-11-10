const { test, expect, createGame, snapshot } = require('./helpers.cjs');

test('mobile battlefield and selection rail', async ({ page }, testInfo) => {
  await page.goto(await createGame(page));
  if (testInfo.project.name === 'mobile-portrait') {
    await expect(page.getByText(/rotate/i).first()).toBeVisible();
    await snapshot(page, 'rotate-prompt');
    return;
  }
  await expect(page.getByRole('group', { name: 'battlefield', exact: true })).toBeVisible();
  await snapshot(page, 'battlefield');
  await page.getByRole('button', { name: /tank 11$/ }).click();
  await snapshot(page, 'orders-rail');
  await page.getByRole('tab', { name: 'details', exact: true }).click();
  await snapshot(page, 'details-rail');
  await page.getByRole('button', { name: 'menu', exact: true }).click();
  await page.getByRole('button', { name: 'settings', exact: true }).click();
  await expect(page.locator('#settings')).toBeVisible();
  await snapshot(page, 'settings');
});
