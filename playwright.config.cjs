const { defineConfig } = require('@playwright/test');

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
    baseURL: 'http://127.0.0.1:4187',
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
    { name: 'mobile-landscape', testMatch: '**/mobile.spec.cjs', use: { viewport: { width: 852, height: 393 }, isMobile: true, hasTouch: true } },
    { name: 'mobile-portrait', testMatch: '**/mobile.spec.cjs', use: { viewport: { width: 393, height: 852 }, isMobile: true, hasTouch: true } },
  ],
  webServer: {
    command: 'npm run test:visual:build && node tests/visual/server.cjs',
    url: 'http://127.0.0.1:4187',
    reuseExistingServer: false,
    timeout: 300_000,
    gracefulShutdown: { signal: 'SIGTERM', timeout: 5_000 },
  },
});
