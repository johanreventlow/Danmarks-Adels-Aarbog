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

// Trin: path, role (null|'medlem'|'redaktion'), me (»Det er mig«-id), fail (databasen svarer 500), w/h,
// actions: click (synlig tekst)|role ([rolle, tilgængeligt navn])|css|fill|key|move|scroll.
const STEPS = [
  { out: 'a-home', path: '/', full: true },
  // Feedet på hovedsiden (fase 4): første uddeling, og knappen vender seks blade mere.
  { out: 'a-home-feed', path: '/', actions: [{ scroll: 600 }] },
  { out: 'a-home-vend', path: '/', actions: [{ scroll: 600 }, { click: 'Vend seks blade mere', exact: true }, { scroll: 900 }] },
  // Hovedsidens tre indgange; slutadresserne skal være /soeg?q=Reventlow, /slaegt/reventlow og /slaegtskab.
  { out: 'a-home-soeg', path: '/', actions: [{ fill: ['#forside-soeg', 'Reventlow'] }, { key: 'Enter' }] },
  { out: 'a-home-register', path: '/', actions: [{ css: 'a[href="/slaegt/reventlow"]:has(> span)' }] },
  { out: 'a-home-familie', path: '/', actions: [{ click: 'Find slægtskabet mellem to personer →', exact: true }] },
  { out: 'a-menu-slaegter', path: '/', actions: [{ click: 'Slægter', exact: true }] },
  { out: 'a-person', path: '/person/118' },
  { out: 'a-personside-fuld', path: '/person/240', full: true }, // testbiografi, fakta og 25 embeder (mockdb)
  { out: 'a-person-ukendt', path: '/person/999999' },
  { out: 'a-personside-embeder', path: '/person/240', actions: [{ click: 'Vis alle 25 embeder og hverv', exact: true }, { scroll: 700 }] },
  { out: 'a-personside-bund', path: '/person/240', actions: [{ scroll: 4000 }] },
  { out: 'a-personside-udgave', path: '/person/240', actions: [{ css: '[role="group"][aria-label="Udgave"] button >> nth=1' }] },
  { out: 'a-personside-aegtefaelle', path: '/person/461' }, // ægtefælle uden linje: ingen slægt i etiket og brødkrumme
  { out: 'a-tree-fokus', path: '/slaegt/reventlow/stamtrae?fokus=118' },
  { out: 'a-tree-panel', path: '/slaegt/reventlow/stamtrae?fokus=240' },
  { out: 'a-personside-mig', path: '/person/240', actions: [{ click: 'Det er mig', exact: true }] },
  { out: 'a-tree-aegteskaber', path: '/slaegt/reventlow/stamtrae?fokus=61' },
  { out: 'a-tree-formodet', path: '/slaegt/reventlow/stamtrae?fokus=38', actions: [{ scroll: 400 }] },
  { out: 'a-tree-en-foraelder', path: '/slaegt/reventlow/stamtrae?fokus=45' },
  { out: 'a-tree-piletaster', path: '/slaegt/reventlow/stamtrae?fokus=61', actions: [{ css: '[role="group"][aria-label^="Søskendeflokken"] [aria-current]' }, { key: 'ArrowRight' }, { key: 'ArrowRight' }, { key: 'ArrowRight' }] },
  { out: 'a-tree-900-panel', path: '/slaegt/reventlow/stamtrae?fokus=61', w: 900, h: 900 },
  { out: 'a-tree-kolonner', path: '/slaegt/reventlow/stamtrae', actions: [{ click: 'Kolonner', exact: true }] },
  { out: 'a-search', path: '/soeg?q=rev' },
  { out: 'a-search-tom', path: '/soeg?q=Reventlov' },
  // Skriver midt i et ord: »Revetlow« → »Reventlow«. Slutadressen skal være /soeg?q=Reventlow.
  // Søgesiden (fase 6b): fremhævning, godser og personer, filtre i adressen, stavemåde-forslag, alle personer.
  { out: 'a-search-conrad', path: '/soeg?q=Conrad' },
  { out: 'a-search-gods', path: '/soeg?q=stamhuset' },
  { out: 'a-search-filtre', path: '/soeg?q=Reventlow&type=personer&fra=1700&til=1750&sort=foedt' },
  { out: 'a-search-forslag', path: '/soeg?q=Revenlow' },
  { out: 'a-search-stavemaader', path: '/soeg?q=Reventlou' },
  { out: 'a-search-alle', path: '/soeg', actions: [{ scroll: 1800 }] },
  { out: 'a-search-midt', path: '/soeg', actions: [{ fill: ['#soegeside-q', 'Revetlow'] }, { key: 'ArrowLeft' }, { key: 'ArrowLeft' }, { key: 'ArrowLeft' }, { key: 'ArrowLeft' }, { key: 'n' }] },
  // Klikvej gennem menu og bjælke; slutadressen skal være stamtræet uden ?fokus=.
  { out: 'a-klikvej', path: '/', actions: [{ click: 'Slægter', exact: true }, { click: 'Reventlow', exact: true }, { click: 'Stamtræ', exact: true }, { click: 'Besiddelser', exact: true }, { click: 'Stamtræ', exact: true }] },
  { out: 'a-monogram', path: '/slaegt/reventlow/stamtrae?fokus=421' },
  { out: 'a-fejl', path: '/', fail: true },
  { out: 'a-relate', path: '/slaegtskab', actions: [{ fill: ['input[role="combobox"] >> nth=0', 'Otto Reventlow'] }, { click: 'ca. 1660' }, { fill: ['input[role="combobox"] >> nth=1', 'Magdalena'] }, { click: 'Magdalena Sophia Reventlow' }] },
  // Er vi i familie? (fase 6a): forslagslisten, et delt link, fætre, et formodet led, ingen forbindelse, ukendt id.
  { out: 'a-relate-vaelger', path: '/slaegtskab', actions: [{ fill: ['input[role="combobox"] >> nth=0', 'Otto'] }] },
  { out: 'a-relate-link', path: '/slaegtskab?a=103&b=125' },
  // Skifter en valgt person ved at skrive i det udfyldte felt (rigtige tastetryk, ikke fill).
  { out: 'a-relate-skift', path: '/slaegtskab?a=103&b=125', actions: [{ css: 'input[role="combobox"] >> nth=0' }, { key: 'H' }, { key: 'a' }, { key: 'r' }, { key: 't' }] },
  { out: 'a-relate-faetre', path: '/slaegtskab?a=20&b=147' },
  { out: 'a-relate-formodet', path: '/slaegtskab?a=18&b=50' },
  { out: 'a-relate-ingen', path: '/slaegtskab?a=103&b=471' },
  { out: 'a-relate-ukendt', path: '/slaegtskab?a=103&b=99999' },
  { out: 'a-estates', path: '/slaegt/reventlow/besiddelser' },
  { out: 'a-kort', path: '/slaegt/reventlow/besiddelser?visning=kort' },
  // Besiddelsens side (fase 7b): mange ejere, blandet med og uden årstal, kun uden årstal, ukendt id.
  { out: 'a-besiddelse', path: '/besiddelse/6' },
  { out: 'a-besiddelse-blandet', path: '/besiddelse/44' },
  { out: 'a-besiddelse-uden-aar', path: '/besiddelse/17' },
  { out: 'a-besiddelse-ukendt', path: '/besiddelse/99999' },
  { out: 'a-arms', path: '/slaegt/reventlow/vaaben' },
  { out: 'a-about', path: '/slaegt/reventlow' },
  { out: 'a-about-hel', path: '/slaegt/reventlow', actions: [{ click: 'Læs hele indledningen', exact: true }] },
  { out: 'a-about-linjer', path: '/slaegt/reventlow', actions: [{ click: 'Om I. linje', exact: true }, { scroll: 500 }] },
  { out: 'a-about-feed', path: '/slaegt/reventlow', actions: [{ scroll: 1200 }] },
  { out: 'a-praesens', path: '/slaegt/reventlow/praesens' },
  { out: 'a-ukendt-slaegt', path: '/slaegt/findes-ikke' },
  { out: 'a-gammel-sti', path: '/estates' }, // skal ende på /slaegt/reventlow/besiddelser
  // Fra før fase 7a: skal ende på /slaegt/reventlow/besiddelser og /besiddelse/<id>.
  { out: 'a-gammel-godser', path: '/slaegt/reventlow/godser' },
  { out: 'a-gammel-gods', path: '/gods/1' },
  { out: 'a-login', path: '/', actions: [{ click: 'Log ind', exact: true }] },
  { out: 'b-member-home', path: '/', role: 'medlem' },
  { out: 'b-member-bookmarks', path: '/min-side/bogmaerker', role: 'medlem' },
  { out: 'b-member-praesens', path: '/slaegt/reventlow/praesens', role: 'medlem' },
  { out: 'b-red-bjaelke', path: '/slaegt/reventlow', role: 'redaktion' },
  { out: 'c-red-anon', path: '/redaktion' },
  { out: 'c-red-redaktion', path: '/redaktion', role: 'redaktion' },
  { out: 'd-mobile-home', path: '/', w: 390, h: 844 },
  { out: 'd-mobile-home-feed', path: '/', w: 390, h: 844, actions: [{ move: [200, 600] }, { scroll: 700 }] },
  { out: 'd-mobile-home-vend', path: '/', w: 390, h: 844, actions: [{ move: [200, 600] }, { scroll: 3200 }, { click: 'Vend seks blade mere', exact: true }, { scroll: 600 }] },
  { out: 'd-mobile-menu', path: '/', w: 390, h: 844, actions: [{ role: ['button', 'Menu'] }, { role: ['button', 'Slægter'] }] },
  { out: 'd-mobile-menu-aaben', path: '/', w: 390, h: 844, actions: [{ role: ['button', 'Menu'] }] },
  { out: 'd-mobile-bjaelke', path: '/slaegt/reventlow/stamtrae', w: 390, h: 844 },
  { out: 'd-mobile-tree-aegteskaber', path: '/slaegt/reventlow/stamtrae?fokus=61', w: 390, h: 844, actions: [{ move: [200, 600] }, { scroll: 300 }] },
  { out: 'd-mobile-tree-panel', path: '/slaegt/reventlow/stamtrae?fokus=240', w: 390, h: 844 },
  { out: 'd-mobile-about', path: '/slaegt/reventlow', w: 390, h: 844 },
  { out: 'd-mobile-besiddelse', path: '/besiddelse/6', w: 390, h: 844 },
  { out: 'd-mobile-search', path: '/soeg?q=Conrad', w: 390, h: 844 },
  { out: 'd-mobile-search-afgraens', path: '/soeg?q=Conrad', w: 390, h: 844, actions: [{ click: 'Afgræns' }] },
  { out: 'd-mobile-relate-vaelger', path: '/slaegtskab', w: 390, h: 844, actions: [{ fill: ['input[role="combobox"] >> nth=0', 'Otto'] }] },
  { out: 'd-mobile-relate', path: '/slaegtskab?a=18&b=50', w: 390, h: 844 },
  { out: 'd-mobile-relate-vej', path: '/slaegtskab?a=18&b=50', w: 390, h: 844, actions: [{ move: [200, 600] }, { scroll: 700 }] },
  { out: 'd-mobile-about-linjer', path: '/slaegt/reventlow', w: 390, h: 844, actions: [{ move: [200, 600] }, { scroll: 900 }] },
  { out: 'd-mobile-person', path: '/person/240', w: 390, h: 844 },
  { out: 'd-mobile-person-bund', path: '/person/240', w: 390, h: 844, actions: [{ move: [200, 600] }, { scroll: 2500 }] },
  // Fase 9 (mobil web): personsiden, søgningen, Er vi i familie? og delte links ved 390 px.
  { out: 'd-mobile-person-fuld', path: '/person/240', w: 390, h: 844, full: true },
  { out: 'd-mobile-person-118', path: '/person/118', w: 390, h: 844, full: true },
  { out: 'd-mobile-person-aegtefaelle', path: '/person/461', w: 390, h: 844 },
  { out: 'd-mobile-person-ukendt', path: '/person/999999', w: 390, h: 844 },
  { out: 'd-mobile-person-embeder', path: '/person/240', w: 390, h: 844, actions: [{ click: 'Vis alle 25 embeder og hverv', exact: true }, { move: [200, 600] }, { scroll: 700 }] },
  { out: 'd-mobile-person-udgave', path: '/person/240', w: 390, h: 844, actions: [{ css: '[role="group"][aria-label="Udgave"] button >> nth=1' }] },
  { out: 'd-mobile-person-slaegtskab', path: '/person/125', me: '103', w: 390, h: 844 },
  { out: 'd-mobile-person-slaegtskab-gift', path: '/person/461', me: '103', w: 390, h: 844 },
  { out: 'd-mobile-person-slaegtskab-ingen', path: '/person/118', me: '240', w: 390, h: 844 },
  { out: 'd-mobile-person-medlem', path: '/person/240', role: 'medlem', w: 390, h: 844, full: true },
  { out: 'd-mobile-search-tom', path: '/soeg?q=Reventlov', w: 390, h: 844 },
  { out: 'd-mobile-search-filtre', path: '/soeg?q=Reventlow&type=personer&fra=1700&til=1750&sort=foedt', w: 390, h: 844 },
  { out: 'd-mobile-search-alle', path: '/soeg', w: 390, h: 844, full: true },
  { out: 'd-mobile-relate-tom', path: '/slaegtskab', w: 390, h: 844 },
  { out: 'd-mobile-relate-link', path: '/slaegtskab?a=103&b=125', w: 390, h: 844, full: true },
  { out: 'd-mobile-relate-faetre', path: '/slaegtskab?a=20&b=147', w: 390, h: 844, full: true },
  { out: 'd-mobile-relate-ingen', path: '/slaegtskab?a=103&b=471', w: 390, h: 844 },
  { out: 'd-mobile-relate-ukendt', path: '/slaegtskab?a=103&b=99999', w: 390, h: 844 },
  { out: 'd-mobile-relate-mig', path: '/slaegtskab', me: '240', w: 390, h: 844 },
  { out: 'd-mobile-login', path: '/', w: 390, h: 844, actions: [{ role: ['button', 'Menu'] }, { role: ['button', 'Log ind'] }] },
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
  if (s.me) await pg.addInitScript((id) => localStorage.setItem('daa_me_id', id), s.me); // »Det er mig«
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
      if (a.role) await pg.getByRole(a.role[0], { name: a.role[1], exact: true }).first().click({ timeout: 4000 }); // ikonknapper
      if (a.css) await pg.locator(a.css).first().click({ timeout: 4000 });
      if (a.fill) await pg.locator(a.fill[0]).first().fill(a.fill[1]);
      if (a.key) await pg.keyboard.press(a.key);
      if (a.move) await pg.mouse.move(a.move[0], a.move[1]); // fx ved 390 px, hvor standardpunktet ligger uden for vinduet
      if (a.scroll) await pg.mouse.wheel(0, a.scroll);
      await pg.waitForTimeout(900);
    } catch (e) { errs.push(`handling ${JSON.stringify(a)}: ${e.message.split('\n')[0]}`); }
  }
  await pg.screenshot({ path: path.join(OUT, `${s.out}.png`), fullPage: !!s.full });
  // Bredere end vinduet: appens skal er 100vh med overflow hidden, så dokumentet bliver aldrig bredere — indhold, der
  // stikker ud, bliver skåret af eller giver vandret scroll i den indre rulleflade. Nævner de yderste elementer, der
  // går ud over vinduets kant, undtagen inde i en bevidst vandret rulleflade (søskendeflokken) eller en klippet tekst
  // (inline overflowX/overflow sat på en forælder under skallen).
  const bred = await pg.evaluate(() => {
    const vw = document.documentElement.clientWidth;
    const skal = document.getElementById('root')?.firstElementChild;
    const bevidst = (el) => { for (let p = el.parentElement; p && p !== skal; p = p.parentElement) { const o = p.style.overflowX || p.style.overflow; if (o && o !== 'visible') return true; } return false; };
    const ud = [...document.body.querySelectorAll('*')].filter((el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.right > vw + 1 && getComputedStyle(el).position !== 'fixed' && !bevidst(el); });
    // Felter under 16 px får iPhone-Safari til at zoome ind ved fokus (kun relevant på smal skærm).
    const smaa = vw > 720 ? [] : [...document.querySelectorAll('input:not([type=checkbox]):not([type=radio]), select, textarea')].filter((el) => el.getBoundingClientRect().width > 0 && parseFloat(getComputedStyle(el).fontSize) < 16)
      .map((el) => `${el.tagName.toLowerCase()}#${el.id || el.getAttribute('aria-label') || el.getAttribute('placeholder') || '?'}=${getComputedStyle(el).fontSize}`);
    if (!ud.length && !smaa.length) return null;
    const yderst = ud.filter((el) => !ud.includes(el.parentElement));
    const navn = (el) => { const t = (el.getAttribute('aria-label') || el.textContent || '').trim().slice(0, 28); return `${el.tagName.toLowerCase()}«${t}»+${Math.round(el.getBoundingClientRect().right - vw)}`; };
    return [ud.length ? `stikker ud: ${yderst.length} elementer: ${yderst.slice(0, 5).map(navn).join(', ')}` : '', smaa.length ? `felt < 16 px: ${smaa.join(', ')}` : ''].filter(Boolean).join('  ');
  });
  const slut = new URL(pg.url()); const adr = slut.pathname + slut.search;
  console.log(`${s.out}${adr !== s.path ? `  → ${adr}` : ''}${bred ? `  ⇔ ${bred}` : ''}${errs.length ? '  ⚠ ' + errs.join(' | ') : ''}${log.length ? '  · ' + [...new Set(log)].join(', ') : ''}`);
  await ctx.close();
}
await browser.close();
