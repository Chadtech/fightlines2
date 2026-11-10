const { test: base, expect } = require('@playwright/test');

const test = base.extend({
  page: async ({ page }, use) => {
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('requestfailed', request => {
      const failure = request.failure()?.errorText;
      // A document navigation intentionally cancels the previous page's requests.
      if (failure !== 'net::ERR_ABORTED') errors.push(`${failure} ${request.url()}`);
    });
    page.on('response', response => {
      if (response.status() >= 400) errors.push(`${response.status()} ${response.url()}`);
    });
    await page.clock.setFixedTime(new Date('2026-01-15T12:00:00Z'));
    await page.addInitScript(() => {
      Math.random = () => 0.42;
      // GamePage's sole 400 ms interval advances idle sprite atlas columns.
      // Reduced motion disables CSS animation, not this Elm subscription.
      // Freeze only that presentation ticker; polling, RAF, and input stay real.
      const setInterval = window.setInterval.bind(window);
      window.setInterval = (callback, delay, ...args) =>
        setInterval(delay === 400 ? () => {} : callback, delay, ...args);
      // Exercise the mobile feature on desktop too: it must not change that layout.
      if (!localStorage.getItem('fightlines.localStorage')) {
        localStorage.setItem('fightlines.localStorage', JSON.stringify({
          audioMuted: true,
          welcomeBriefingDismissed: true,
          skipTurnIntroduction: true,
          features: ['mobileLandscape'],
        }));
      }
    });
    await use(page);
    expect(errors, 'browser errors and failed HTTP responses').toEqual([]);
  },
});

async function graphql(page, query) {
  const response = await page.request.post('/graphql', { data: { query } });
  expect(response.ok(), await response.text()).toBeTruthy();
  const body = await response.json();
  expect(body.errors, 'GraphQL setup must use the real server successfully').toBeUndefined();
  return body.data;
}

async function createGame(page) {
  const { createLobby } = await graphql(page,
    'mutation { createLobby(name: "commander", lobbyName: "visual patrol") { id } }');
  const id = JSON.stringify(createLobby.id);
  await graphql(page, `mutation { setLobbyController(id: ${id}, controller: AI) { id } }`);
  await graphql(page, `mutation { startGame(id: ${id}) { id } }`);
  return `/game/${createLobby.id}`;
}

async function openGame(page) {
  await page.goto(await createGame(page));
  await expect(page.getByRole('group', { name: 'battlefield', exact: true })).toBeVisible();
}

async function snapshot(page, name) {
  await page.mouse.move(0, 0);
  await page.evaluate(async () => {
    await document.fonts.ready;
    if (!document.fonts.check('16px "Ubuntu Mono"')) throw new Error('Game font not ready');
    const urls = new Set();
    for (const image of document.querySelectorAll('img, svg image')) {
      const source = image.currentSrc || image.getAttribute('src') || image.getAttribute('href') || image.getAttribute('xlink:href');
      if (source && !source.startsWith('#')) urls.add(source);
    }
    for (const element of document.querySelectorAll('*')) {
      for (const match of getComputedStyle(element).backgroundImage.matchAll(/url\(["']?([^"')]+)["']?\)/g)) urls.add(match[1]);
    }
    await Promise.all([...urls].map(source => new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => image.decode().then(resolve, reject);
      image.onerror = () => reject(new Error(`Could not load visual asset: ${source}`));
      image.src = source;
    })));
  });
  await expect(page).toHaveScreenshot(`${name}.png`, {
    // Release metadata changes on every check-in, not the interface under test.
    stylePath: require.resolve('./screenshot.css'),
  });
}

module.exports = { test, expect, graphql, createGame, openGame, snapshot };
