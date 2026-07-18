import { existsSync } from 'node:fs';
import { defineConfig, devices } from '@playwright/test';

// Nogle sandboxede udviklingsmiljøer forudinstallerer en Chromium-build (ofte en let ældre
// revision) uden for Playwrights egen cache og uden internetadgang til `playwright install`.
// Findes den kendte sti, bruges den eksplicit; findes den IKKE (normal CI/dev-maskine med
// `npx playwright install` kørt), falder vi tilbage til Playwrights egen browser-resolution.
const SANDBOX_CHROMIUM = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const executablePath = existsSync(SANDBOX_CHROMIUM) ? SANDBOX_CHROMIUM : undefined;
const port = Number(process.env.PLAYWRIGHT_PORT ?? 5173);
const baseURL = `http://localhost:${port}`;

// Minimal e2e-opsætning (fase1-design.md §7, task 11) — bootstrappet her, da der ikke
// fandtes en eksisterende Playwright-konfiguration i repoet forud for denne spec (kun
// devDependency'en var på plads). Starter Vite dev-serveren og kører mod den; testene
// mocker ALLE Supabase-kald på netværksniveau (page.route) — der kræves ingen levende
// database. Bruger det præinstallerede Chromium i sandboxede miljøer (se README/miljønoter).
export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: 'list',
  use: {
    baseURL,
    trace: 'retain-on-failure',
  },
  webServer: {
    command: `npm run dev -- --port ${port} --strictPort`,
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        ...(executablePath ? { launchOptions: { executablePath } } : {}),
      },
    },
  ],
});
