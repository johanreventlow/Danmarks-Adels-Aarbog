// Ægte browserverifikation af 1939-tekstfladen (spec §10.5).
//
// Ikke jsdom. Fase 1 kostede fire fejl som udelukkende en rigtig browser fandt:
// en uparsebar scriptblok (blank side), en tom kasse der læstes som frikendelse,
// manglende fremdrift, og kontekst der rakte ud over spændets kant. Ingen af dem
// var synlige i en diff eller en jsdom-kørsel.
//
// Brug:
//   node .claude/skills/daa-extract/scripts/verify_boundary_text_browser.mjs \
//     <sti-til-html> <sti-til-calamari-tekst>
//
// Playwright hentes fra web/node_modules, så scriptet kan køres fra repo-roden.
// Printer KUN tal og status — aldrig tekstindhold; work/ indeholder PII.

import { createRequire } from 'node:module';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '../../../..');
const { chromium } = createRequire(join(repoRoot, 'web', 'package.json'))('playwright');

const FORVENTET = { graenser: 446, huller: 97, pdfsider: 86, ejerloeseTegn: 45757,
                    forslag: 61, signaler: 12 };

const htmlPath = resolve(process.argv[2]);
const sourcePath = resolve(process.argv[3]);
const source = readFileSync(sourcePath, 'utf8');

const results = [];
const record = (name, ok, detail) => {
  results.push({ name, ok });
  console.log(`${ok ? 'OK  ' : 'FEJL'}  ${name}${detail ? ` — ${detail}` : ''}`);
};

const browser = await chromium.launch();
const context = await browser.newContext({ acceptDownloads: true });
const page = await context.newPage();

const pageErrors = [];
page.on('pageerror', error => pageErrors.push(String(error)));
page.on('console', message => {
  if (message.type() === 'error') pageErrors.push(`console: ${message.text()}`);
});

await page.goto(`file://${htmlPath}`);
await page.waitForLoadState('networkidle');

// 1. Fladen renderer, og scriptblokken kastede ikke.
const box = page.locator('textarea').first();
await box.waitFor({ state: 'visible', timeout: 15000 });
record('fladen renderer med en tekstboks', true);
record('ingen JavaScript-fejl ved indlæsning', pageErrors.length === 0,
  pageErrors.length ? pageErrors.slice(0, 3).join(' | ') : 'ingen');

// 2. Teksten er komplet, og bogens egne sidemarkører er intakte.
//
// Fladen viser én bogside ad gangen, så tekstboksen rummer kun et udsnit. Hele
// dokumentet samles ved at bladre listen igennem — at måle på den synlige side og
// kalde det dokumentet ville være samme fejl som resten af denne fil advarer mod.
const pageButtons = page.locator('button[data-action="select-page"], button:has-text("PDF-side")');
const pageCount = await pageButtons.count();
record(`sidelisten har ${FORVENTET.pdfsider} rækker`,
  pageCount === FORVENTET.pdfsider, `fandt ${pageCount}`);

const pageTexts = [];
for (let index = 0; index < pageCount; index += 1) {
  await pageButtons.nth(index).click();
  pageTexts.push(await box.inputValue());
}
await pageButtons.nth(0).click();
const value = pageTexts.join('\n');

// Sidelisten er navigationen nu, hvor browserens søgning kun når den synlige side.
// Dens tal skal derfor summe til helheden — ellers skjuler sideopdelingen netop det,
// fladen findes for at vise.
const listRows = (await page.locator('body').innerText())
  .split('\n').filter(row => /^PDF-side \d+/.test(row));
const listSum = label => listRows.reduce((total, row) =>
  total + Number((row.match(new RegExp(`(\\d+) ${label}`)) || [0, 0])[1]), 0);

const sourcePages = (source.match(/^### PAGE \d+ ###$/gm) || []).length;
const shownPages = (value.match(/^### PAGE \d+ ###$/gm) || []).length;
record('bogens egne ###-sidemarkører er intakte',
  shownPages === sourcePages, `kilde ${sourcePages}, vist ${shownPages}`);
record('teksten er komplet', value.length >= source.length,
  `kilde ${source.length} tegn, vist ${value.length} tegn (+${value.length - source.length} markør)`);

const markers = {
  graense: (value.match(/^=== GRÆNSESKÆRING(?: · SIGNAL [^=]*)? ===$/gm) || []).length,
  forslag: (value.match(/^=== FORSLAG\? SKÆRING ===$/gm) || []).length,
  signaler: (value.match(/^=== GRÆNSESKÆRING · SIGNAL [^=]* ===$/gm) || []).length,
  ejerloes: (value.match(/^=== EJERLØS TEKST · \d+ tegn ===$/gm) || []).length,
  ejerloesSlut: (value.match(/^=== SLUT EJERLØS TEKST ===$/gm) || []).length,
  pdfside: (value.match(/^=== PDF-SIDE \d+ ===$/gm) || []).length,
};
console.log(`      markører: ${JSON.stringify(markers)}`);
const modelCounts = await page.evaluate('({ graenser: DATA.expectedBoundaryOffsets.length, forslag: DATA.expectedProposalOffsets.length })');
record(`${FORVENTET.graenser} grænser findes i det forudsatte modelsæt`,
  modelCounts.graenser === FORVENTET.graenser, `fandt ${modelCounts.graenser}`);
record(`${FORVENTET.forslag} forslag findes i det forudsatte modelsæt`,
  modelCounts.forslag === FORVENTET.forslag, `fandt ${modelCounts.forslag}`);
record('sidelistens ejerløs-tal summer til de viste startmarkører',
  listSum('ejerløs') === markers.ejerloes, `${listSum('ejerløs')} / ${markers.ejerloes}`);
record('sidelistens forslag-tal summer til de viste forslag',
  listSum('forslag') === markers.forslag, `${listSum('forslag')} / ${markers.forslag}`);
record('sidelistens signal-tal summer til de viste signalmarkører',
  listSum('signal') === markers.signaler, `${listSum('signal')} / ${markers.signaler}`);
record(`kun huller med rigtig tekst får banner (${FORVENTET.huller})`,
  markers.ejerloes === FORVENTET.huller, `fandt ${markers.ejerloes}`);
record('hvert ejerløst hul har en slutmarkør',
  markers.ejerloesSlut === FORVENTET.huller, `fandt ${markers.ejerloesSlut}`);
record(`${FORVENTET.pdfsider} PDF-sidelinjer`,
  markers.pdfside === FORVENTET.pdfsider, `fandt ${markers.pdfside}`);

// Kant-hullerne må ikke være forsvundet: de to kanter er 868 og 6.330 tegn, og de
// faldt oprindeligt ud, fordi de mangler en nabo på den ene side.
record('dokumentets kant-huller (868 og 6.330 tegn) er annonceret',
  value.includes('=== EJERLØS TEKST · 6330 tegn ===')
  && value.includes('=== EJERLØS TEKST · 868 tegn ==='));

// Antallet alene beviser ikke at det er de RIGTIGE huller: summen skal ramme den
// målte mængde ejerløs tekst med indhold.
const bannerSum = [...value.matchAll(/^=== EJERLØS TEKST · (\d+) tegn ===$/gm)]
  .reduce((total, match) => total + Number(match[1]), 0);
record('bannerne dækker de målte 45.757 ejerløse tegn',
  bannerSum === FORVENTET.ejerloeseTegn, `sum ${bannerSum}`);

// En godkendt forslagstekst kan dele vist linjestart med en allerede importeret
// brugerskæring. De to ens SKÆRING-linjer skal konsumere hver sin kanoniske mapping,
// og listeetiketten skal stemme med regnskabet.
const proposalAccounting = await page.evaluate(() => {
  const sourceText = 'A \nB\n';
  return globalThis.DAABoundaryText.buildExport(
    'A \n=== SKÆRING ===\n=== SKÆRING ===\nB\n',
    {
      sourceText, source: {}, expectedBoundaryOffsets: [], expectedProposalOffsets: [3],
      lineMarkerMappings: [
        { kind: 'proposal', text: '=== FORSLAG? SKÆRING ===', canonicalOffset: 3, displayOffset: 3 },
        { kind: 'cut', text: '=== SKÆRING ===', canonicalOffset: 1, displayOffset: 3, origin: 'bruger' },
      ],
    },
    '2026-08-10T10:00:00.000Z',
  );
});
record('in-place-godkendt forslag bogføres levende ved samplacerede skæringer',
  proposalAccounting.ok
  && proposalAccounting.value.aendringsregnskab.forslag_godkendt === 1
  && proposalAccounting.value.skaeringer.some(item => item.oprindelse === 'forslag_godkendt'));

// 3. Gaten reagerer løbende — ikke først ved eksport.
//
// Linjenummeret skal vælges bevidst: fladen består af både bogtekst og markører,
// og de to slags ændring er forskellige fund. En blind nedadpil ramte tidligere en
// markørlinje og målte dermed noget andet end den troede.
const lines = (await box.inputValue()).split('\n');
const isMarker = line => line.startsWith('===');
const isSourcePage = line => line.startsWith('###');
const bookLine = lines.findIndex(line =>
  line.trim() && !isMarker(line) && !isSourcePage(line));
const markerLine = lines.findIndex(isMarker);

const statusText = async () => (await page.locator('body').innerText())
  .split('\n').filter(line => /urørt|ændret|ukendt|markør|bogtekst/i.test(line)).join(' | ');

record('gate-status vises inden ændring', /urørt/i.test(await statusText()));

// Caret sættes på nøjagtig tegnposition. ArrowDown flytter sig efter OMBRUDTE
// linjer i en tekstboks, ikke efter rigtige linjer — en tidligere udgave af denne
// test redigerede derfor et helt andet sted, end den troede, og målte fladen forkert.
const typeOnLine = async (index, keystroke) => {
  await page.evaluate(lineIndex => {
    const field = document.querySelector('textarea');
    const caret = field.value.split('\n').slice(0, lineIndex + 1).join('\n').length;
    field.focus();
    field.setSelectionRange(caret, caret);
  }, index);
  await page.keyboard.type(keystroke);
  await page.waitForTimeout(900); // debounce
};

await typeOnLine(bookLine, 'X');
const afterBook = await statusText();
record('gaten fanger én indsat karakter i bogteksten',
  /ændret/i.test(afterBook), `linje ${bookLine + 1} · ${afterBook.slice(0, 120)}`);
record('gaten peger på et linjenummer', /linje\s*\d+/i.test(afterBook));

await page.keyboard.press('Backspace');
await page.waitForTimeout(900);
record('gaten er grøn igen efter fortrydelse', /urørt/i.test(await statusText()));

// En ødelagt markørlinje er et andet fund end en ændret bogtekst — begge skal fanges.
await typeOnLine(markerLine, 'X');
const afterMarker = await statusText();
record('en ødelagt markørlinje fanges som ukendt markør',
  /ukendt/i.test(afterMarker), `linje ${markerLine + 1} · ${afterMarker.slice(0, 120)}`);
await page.keyboard.press('Backspace');
await page.waitForTimeout(900);

// UDELAD efter første ikke-blanke tegn på en linje bevarer bogteksten byte-for-byte,
// men skal give en levende formadvarsel. Vælg en rigtig linje uden eksisterende tags
// og sæt markeringen med setSelectionRange-uafhængig, deterministisk strengredigering.
const beforeOmissionWarning = await box.inputValue();
const warningLines = beforeOmissionWarning.split('\n');
let omissionDepth = 0;
let warningLine = -1;
for (let index = 0; index < warningLines.length; index += 1) {
  const line = warningLines[index];
  const opens = (line.match(/\[\[UDELAD\]\]/g) || []).length;
  const closes = (line.match(/\[\[\/UDELAD\]\]/g) || []).length;
  if (omissionDepth === 0 && opens === 0 && closes === 0
      && /^\S.{2,}$/u.test(line) && !line.startsWith('===') && !line.startsWith('###')) {
    warningLine = index;
    break;
  }
  omissionDepth += opens - closes;
}
record('fandt en boglinje til ét-tegnsadvarslen', warningLine >= 0, `linje ${warningLine + 1}`);
if (warningLine >= 0) {
  const line = warningLines[warningLine];
  const [firstCharacter, ...rest] = Array.from(line);
  warningLines[warningLine] = `${firstCharacter}[[UDELAD]]${rest.join('')}[[/UDELAD]]`;
  await box.fill(warningLines.join('\n'));
  await page.waitForTimeout(900);
  const warningText = await page.locator('[data-role="omission-warning"]').innerText();
  record('fladen advarer levende om det efterladte tegn',
    /efterlader ét ikke-blankt tegn/i.test(warningText), warningText);
  record('én-tegnsadvarslen ændrer ikke byte-gaten', /urørt/i.test(await statusText()));
  await box.fill(beforeOmissionWarning);
  await page.waitForTimeout(900);
  record('advarslen forsvinder når markeringen rettes',
    (await page.locator('[data-role="omission-warning"]').innerText()) === '');
}

// Bryd gaten igen, så eksport-blokeringen nedenfor måler det den tror.
await typeOnLine(bookLine, 'X');
record('gaten er brudt inden eksport-forsøget', /ændret/i.test(await statusText()));

// 4. Eksport skal være umulig — ikke frarådet — mens gaten er brudt.
const exportButton = page.locator('button', { hasText: /eksport/i }).first();
const hasExport = await exportButton.count() > 0;
record('eksportknap findes', hasExport);

if (hasExport) {
  const blocked = await Promise.race([
    page.waitForEvent('download', { timeout: 3000 }).then(() => 'download'),
    exportButton.click().then(() => page.waitForTimeout(2500)).then(() => 'ingen'),
  ]).catch(() => 'ingen');
  record('eksport blokeret mens gaten er brudt', blocked === 'ingen', `resultat: ${blocked}`);
}

// 5. Gendan, eksportér, kontrollér filnavn og format.
await page.keyboard.press('Backspace');
await page.waitForTimeout(900);
record('gaten bliver grøn igen når tegnet fjernes', /urørt/i.test(await statusText()));

if (hasExport) {
  const [download] = await Promise.all([
    page.waitForEvent('download', { timeout: 10000 }),
    exportButton.click(),
  ]);
  const name = download.suggestedFilename();
  record('eksportfilnavn', name === '1939-graenseflade.json', name);
  const target = join(mkdtempSync(join(tmpdir(), 'graenseflade-')), 'eksport.json');
  await download.saveAs(target);
  const draft = JSON.parse(readFileSync(target, 'utf8'));
  record('eksport har de aftalte felter',
    ['schema_version', 'source', 'skaeringer', 'aendringsregnskab'].every(key => key in draft),
    Object.keys(draft).join(', '));
  const regnskab = draft.aendringsregnskab || {};
  record('ændringsregnskabet summer',
    (regnskab.beholdt ?? -1) + (regnskab.slettet ?? -1) === FORVENTET.graenser,
    JSON.stringify(regnskab));
  record('viste forudsatte grænser matcher regnskabets beholdte',
    markers.graense === regnskab.beholdt, `${markers.graense} / ${regnskab.beholdt}`);
  record('forslagsoprindelser matcher regnskabets godkendte',
    draft.skaeringer.filter(item => item.oprindelse === 'forslag_godkendt').length
      === regnskab.forslag_godkendt,
    `${draft.skaeringer.filter(item => item.oprindelse === 'forslag_godkendt').length} / ${regnskab.forslag_godkendt}`);
  record('den redigerede tekst eksporteres IKKE',
    !JSON.stringify(draft).includes('=== GRÆNSESKÆRING ==='));
}

// Kvitteringen er det eneste, der gør "antal manglende sider" ærligt — den skal
// tælle ned, og den må ikke kunne gives mens siden har en fejl.
const tael = async () => ((await page.locator('body').innerText())
  .split('\n').find(row => /af \d+ ·/.test(row)) || '');
const missingPage = page.locator('[data-role="page-list"] button', { hasText: /mangler/ }).first();
if (await missingPage.count()) await missingPage.click();
const faerdig = page.locator('[data-action="complete-page"]').first();
record('kvitteringen er mulig når gaten er grøn', !(await faerdig.isDisabled()));
const foer = await tael();
await faerdig.click();
await page.waitForTimeout(500);
const efter = await tael();
record('kvitteringen tæller manglende sider ned', foer !== efter && /mangler/.test(efter),
  `${foer} → ${efter}`);

await browser.close();

const failed = results.filter(result => !result.ok).length;
console.log(`\n${results.length - failed}/${results.length} kontroller bestået`);
process.exit(failed ? 1 : 0);
