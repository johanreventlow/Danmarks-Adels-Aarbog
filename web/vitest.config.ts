import { defineConfig, configDefaults } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    setupFiles: ['./src/test/setup.ts'],
    // e2e/ er Playwright-specs (task 11) — anden test-runner, egen 'test'-global; ville
    // ellers kollidere med vitest's egen 'test' hvis den forsøgte at samle filerne op.
    exclude: [...configDefaults.exclude, 'e2e/**'],
  },
});
