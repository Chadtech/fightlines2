const { defineConfig } = require('@playwright/test');

const desktopUrl = 'http://127.0.0.1:4187';
const mobileUrl = 'http://127.0.0.1:4188';
const mobileInteractionUrl = 'http://127.0.0.1:4189';
const mobileInteraction = /@mobile-interaction/;
const mobileLandscape = { viewport: { width: 852, height: 393 }, isMobile: true, hasTouch: true };
const serverOptions = {
  reuseExistingServer: false,
  timeout: 300_000,
  gracefulShutdown: { signal: 'SIGTERM', timeout: 5_000 },
};

module.exports = defineConfig({
  testDir: './tests/visual',
  testMatch: '**/*.spec.cjs',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  forbidOnly: !!process.env.CI,
  timeout: 45_000,
  expect: {
    timeout: 10_000,
    toHaveScreenshot: {
      animations: 'disabled',
      caret: 'hide',
      scale: 'css',
      threshold: 0.1,
      maxDiffPixels: 0,
    },
  },
  // Missing baselines must fail normal runs, including CI. Updating is explicit.
  updateSnapshots: 'none',
  snapshotPathTemplate: `{testDir}/baselines/{platform}-${process.arch}/{projectName}/{arg}{ext}`,
  outputDir: 'test-results/visual',
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'playwright-report' }]],
  use: {
    baseURL: desktopUrl,
    browserName: 'chromium',
    // Software rasterization avoids GPU-dependent image resampling noise.
    launchOptions: { args: ['--disable-gpu'] },
    deviceScaleFactor: 1,
    locale: 'en-US',
    timezoneId: 'UTC',
    colorScheme: 'light',
    reducedMotion: 'reduce',
    serviceWorkers: 'block',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'desktop', testMatch: '**/desktop.spec.cjs', use: { viewport: { width: 1440, height: 900 } } },
    { name: 'laptop', testMatch: '**/desktop.spec.cjs', use: { viewport: { width: 1280, height: 800 } } },
    { name: 'mobile-landscape', testMatch: '**/mobile.spec.cjs', grepInvert: mobileInteraction, use: { ...mobileLandscape, baseURL: mobileUrl } },
    { name: 'mobile-interaction', testMatch: '**/mobile.spec.cjs', grep: mobileInteraction, use: { ...mobileLandscape, baseURL: mobileInteractionUrl } },
    { name: 'mobile-portrait', testMatch: '**/mobile-portrait.spec.cjs', use: { baseURL: mobileUrl, viewport: { width: 393, height: 852 }, isMobile: true, hasTouch: true } },
  ],
  // Build once, then give each test group its own lobby creation budget.
  webServer: [
    {
      ...serverOptions,
      command: 'npm run test:visual:build && node tests/visual/server.cjs 4187',
      url: desktopUrl,
    },
    {
      ...serverOptions,
      command: 'node tests/visual/server.cjs 4188',
      url: mobileUrl,
    },
    {
      ...serverOptions,
      command: 'node tests/visual/server.cjs 4189',
      url: mobileInteractionUrl,
    },
  ],
});
