const { test, expect, createGame, snapshot } = require('./helpers.cjs');

test('mobile rotate prompt', async ({ page }) => {
  await page.goto(await createGame(page));
  await expect(page.getByText('turn your phone for landscape orientation', { exact: true })).toBeVisible();
  await snapshot(page, 'rotate-prompt');
});
