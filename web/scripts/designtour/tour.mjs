// Designtour: skærmbilleder af webappen som anonym, medlem og redaktør — mod testdata.
// Forudsætter: `python3 web/scripts/designtour/build-fixture.py` og `npm run dev` (port 5173) i web/.
// Kør fra web/: node scripts/designtour/tour.mjs [filter]   → billeder i ../tmp/designtour/shots/
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
process.env.FIXTURE ??= path.join(ROOT, 'tmp/designtour/fixture.json');
const { handle, state, log } = await import('./mockdb.mjs');
const BASE = process.env.BASE_URL ?? 'http://localhost:5173';
const OUT = path.join(ROOT, 'tmp/designtour/shots');
fs.mkdirSync(OUT, { recursive: true });

// Trin: path, role (null|'medlem'|'redaktion'), fail (databasen svarer 500), w/h, actions: click|css|fill|key|scroll.
const STEPS = [
  { out: 'a-home', path: '/', full: true },
  { out: 'a-menu-slaegter', path: '/', actions: [{ click: 'Slægter', exact: true }] },
  { out: 'a-person', path: '/person/118' },
  { out: 'a-personside-fuld', path: '/person/240', full: true }, // testbiografi, fakta og 25 embeder (mockdb)
  { out: 'a-person-ukendt', path: '/person/999999' },
  { out: 'a-tree-fokus', path: '/slaegt/reventlow/stamtrae?fokus=118' },
  { out: 'a-tree-kolonner', path: '/slaegt/reventlow/stamtrae', actions: [{ click: 'Kolonner', exact: true }] },
  { out: 'a-search', path: '/soeg?q=rev' },
  { out: 'a-search-tom', path: '/soeg?q=Reventlov' },
  // Skriver midt i et ord: »Revetlow« → »Reventlow«. Slutadressen skal være /soeg?q=Reventlow.
  { out: 'a-search-midt', path: '/soeg', actions: [{ fill: ['input[aria-label="Søg person"]', 'Revetlow'] }, { key: 'ArrowLeft' }, { key: 'ArrowLeft' }, { key: 'ArrowLeft' }, { key: 'ArrowLeft' }, { key: 'n' }] },
  // Klikvej gennem menu og bjælke; slutadressen skal være stamtræet uden ?fokus=.
  { out: 'a-klikvej', path: '/', actions: [{ click: 'Slægter', exact: true }, { click: 'Reventlow', exact: true }, { click: 'Stamtræ', exact: true }, { click: 'Godser', exact: true }, { click: 'Stamtræ', exact: true }] },
  { out: 'a-monogram', path: '/slaegt/reventlow/stamtrae?fokus=421' },
  { out: 'a-fejl', path: '/', fail: true },
  { out: 'a-relate', path: '/slaegtskab', actions: [{ fill: ['input[aria-label="Søg person"]', 'Otto Reventlow'] }, { click: 'Otto Reventlow', exact: true }, { fill: ['input[aria-label="Søg person"]', 'Magdalena'] }, { click: 'Magdalena Sophia Reventlow' }] },
  { out: 'a-estates', path: '/slaegt/reventlow/godser' },
  { out: 'a-kort', path: '/slaegt/reventlow/godser?visning=kort' },
  { out: 'a-arms', path: '/slaegt/reventlow/vaaben' },
  { out: 'a-about', path: '/slaegt/reventlow' },
  { out: 'a-praesens', path: '/slaegt/reventlow/praesens' },
  { out: 'a-ukendt-slaegt', path: '/slaegt/findes-ikke' },
  { out: 'a-gammel-sti', path: '/estates' }, // skal ende på /slaegt/reventlow/godser
  { out: 'a-login', path: '/', actions: [{ click: 'Log ind', exact: true }] },
  { out: 'b-member-home', path: '/', role: 'medlem' },
  { out: 'b-member-bookmarks', path: '/min-side/bogmaerker', role: 'medlem' },
  { out: 'b-member-praesens', path: '/slaegt/reventlow/praesens', role: 'medlem' },
  { out: 'b-red-bjaelke', path: '/slaegt/reventlow', role: 'redaktion' },
  { out: 'c-red-anon', path: '/redaktion' },
  { out: 'c-red-redaktion', path: '/redaktion', role: 'redaktion' },
  { out: 'd-mobile-home', path: '/', w: 390, h: 844 },
  { out: 'd-mobile-menu', path: '/', w: 390, h: 844, actions: [{ click: 'Slægter', exact: true }] },
  { out: 'd-mobile-bjaelke', path: '/slaegt/reventlow/stamtrae', w: 390, h: 844 },
  { out: 'd-mobile-person', path: '/person/240', w: 390, h: 844 },
];

const filter = process.argv[2];
const browser = await chromium.launch();
for (const s of STEPS.filter((x) => !filter || x.out.includes(filter))) {
  state.role = s.role ?? null; state.fail = !!s.fail; log.length = 0;
  const ctx = await browser.newContext({ viewport: { width: s.w ?? 1440, height: s.h ?? 900 } });
  const pg = await ctx.newPage();
  const errs = [];
  pg.on('pageerror', (e) => errs.push(e.message));
  await pg.route(/localhost:54321/, handle); // VITE_SUPABASE_URL i .env.local (lokal stack)
  await pg.route(/openstreetmap|carto|tiles?\./, (r) => r.abort());
  if (s.role) {
    // Simuleret session (ingen rigtige legitimationsoplysninger) i supabase-js' localStorage-nøgle.
    const exp = Math.floor(Date.now() / 1000) + 36000;
    const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const sess = { access_token: `${b64({ alg: 'none' })}.${b64({ sub: state.userId, exp, role: 'authenticated' })}.x`, token_type: 'bearer', expires_in: 36000, expires_at: exp, refresh_token: 'r',
      user: { id: state.userId, aud: 'authenticated', role: 'authenticated', email: state.email, app_metadata: {}, user_metadata: {} } };
    await pg.addInitScript(([k, v]) => localStorage.setItem(k, JSON.stringify(v)), ['sb-localhost-auth-token', sess]);
  }
  await pg.goto(BASE + s.path, { waitUntil: 'networkidle' });
  await pg.mouse.move(700, 880); // væk fra sidehovedet, så megamenuen ikke folder ud
  await pg.waitForTimeout(1500);
  for (const a of s.actions ?? []) {
    try {
      if (a.click) await pg.getByText(a.click, { exact: !!a.exact }).first().click({ timeout: 4000 });
      if (a.css) await pg.locator(a.css).first().click({ timeout: 4000 });
      if (a.fill) await pg.locator(a.fill[0]).first().fill(a.fill[1]);
      if (a.key) await pg.keyboard.press(a.key);
      if (a.scroll) await pg.mouse.wheel(0, a.scroll);
      await pg.waitForTimeout(900);
    } catch (e) { errs.push(`handling ${JSON.stringify(a)}: ${e.message.split('\n')[0]}`); }
  }
  await pg.screenshot({ path: path.join(OUT, `${s.out}.png`), fullPage: !!s.full });
  const slut = new URL(pg.url()); const adr = slut.pathname + slut.search;
  console.log(`${s.out}${adr !== s.path ? `  → ${adr}` : ''}${errs.length ? '  ⚠ ' + errs.join(' | ') : ''}${log.length ? '  · ' + [...new Set(log)].join(', ') : ''}`);
  await ctx.close();
}
await browser.close();
