import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: 'test/ui',
  workers: 1,
  use: {
    ...devices['Desktop Chrome'],
    baseURL: process.env.UI_BASE_URL || 'http://127.0.0.1:4107',
    trace: 'retain-on-failure',
  },
  outputDir: 'tmp/ui/results',
});
