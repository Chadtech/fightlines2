const { test, expect, createGame, graphql, snapshot } = require('./helpers.cjs');

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

test('resolved turn report and actions fit short landscape screens', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile-portrait', 'Battlefield requires landscape.');
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
  for (const [width, height] of [[852, 393], [828, 379], [667, 320]]) {
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
  await snapshot(page, 'resolved-turn-report');
  await page.setViewportSize({ width: 828, height: 379 });
  await snapshot(page, 'resolved-turn-report-roomy');
  await dialog.getByRole('button', { name: 'begin turn', exact: true }).click();
  await expect(dialog).toHaveCount(0);
});
