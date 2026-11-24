import { defineConfig, configDefaults } from 'vitest/config';

export default defineConfig({
  // Review 37 C11: mobilen trækker React 19 ind i rodens node_modules; web og dets tests skal altid ramme web's
  // egen React 18 (to Reacts i én render giver »Invalid hook call«).
  resolve: { dedupe: ['react', 'react-dom'] },
  test: {
    globals: true,
    environment: 'node',
    setupFiles: ['./src/test/setup.ts'],
    // e2e/ er Playwright-specs (task 11) — anden test-runner, egen 'test'-global; ville
    // ellers kollidere med vitest's egen 'test' hvis den forsøgte at samle filerne op.
    // scripts/ bruger node:test (PostgREST-gaten, 5c-2/B11) og køres af sit eget CI-trin.
    exclude: [...configDefaults.exclude, 'e2e/**', 'scripts/**'],
  },
});
