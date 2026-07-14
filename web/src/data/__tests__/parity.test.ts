// Mekanisk paritets-test: håndhæver at den delte generations-kerne forbliver tegn-for-tegn ens
// mellem web og mobil. Indtil nu blev det kun tjekket manuelt med `diff` — denne test fejler CI
// hvis en af de fire funktioner drifter mellem platformene (design-spec T5).
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const webTree = readFileSync(join(__dirname, '../tree.ts'), 'utf8');
const mobileSelectors = readFileSync(
  join(__dirname, '../../../../mobile/src/data/selectors.ts'),
  'utf8',
);

// Finder kilde-teksten for `function <name>(...) { ... }` (med eller uden `export`), inklusive
// signatur og krop. Brace-matching håndterer return-type-objektlitteraler (fx
// `buildAnchorPeers`s `: { people: ...; overflow: number }` før selve funktions-kroppen) ved at
// hoppe videre hvis den første balancerede brace efterfølges (efter whitespace/union-suffiks som
// `| null`) af endnu en `{` — ellers var brace'n allerede kroppen. Fejler højlydt hvis funktionen
// ikke findes, eller hvis en brace-gruppe aldrig balancerer (ingen tavs false-positive-match).
function extractFn(src: string, name: string): string {
  const headRe = new RegExp(`(?:^|\\n)(?:export\\s+)?function\\s+${name}\\s*\\(`);
  const headMatch = headRe.exec(src);
  if (!headMatch) throw new Error(`extractFn: fandt ikke funktionen "${name}"`);
  const start = headMatch.index + (src[headMatch.index] === '\n' ? 1 : 0);

  const parenOpen = src.indexOf('(', headMatch.index);
  let depth = 0;
  let i = parenOpen;
  for (; i < src.length; i++) {
    if (src[i] === '(') depth++;
    else if (src[i] === ')') {
      depth--;
      if (depth === 0) break;
    }
  }
  if (i >= src.length) throw new Error(`extractFn: ubalanceret parameterliste for "${name}"`);
  const parenClose = i;

  function matchBrace(openIdx: number): number {
    let d = 0;
    for (let j = openIdx; j < src.length; j++) {
      if (src[j] === '{') d++;
      else if (src[j] === '}') {
        d--;
        if (d === 0) return j;
      }
    }
    throw new Error(`extractFn: ubalancerede braces for "${name}"`);
  }

  let braceStart = src.indexOf('{', parenClose);
  if (braceStart === -1) throw new Error(`extractFn: fandt ingen krop for "${name}"`);
  let braceEnd = matchBrace(braceStart);

  // Efter en balanceret brace: hvis det næste "rigtige" tegn (efter whitespace/union-type-suffiks
  // som `| null`, `[]`, `<T>`) ER en ny `{`, var den forrige brace en del af return-typen —
  // ikke funktionens krop. Spring videre til den næste balancerede brace.
  const suffixRe = /^[\s|&()\w$.[\]<>,:'"`-]*/;
  const suffixMatch = suffixRe.exec(src.slice(braceEnd + 1));
  const afterSuffix = braceEnd + 1 + (suffixMatch ? suffixMatch[0].length : 0);
  if (src[afterSuffix] === '{') {
    braceStart = afterSuffix;
    braceEnd = matchBrace(braceStart);
  }

  return src.slice(start, braceEnd + 1);
}

// generations.ts er ekstraheret til @daa/core (spike-task 1) — findes nu ét sted, så
// buildGenCoords/buildParentsUnknown kan ikke længere drifte mellem to kopier. Tree.ts/
// selectors.ts er ikke ekstraheret endnu (senere task) og paritetstjekkes stadig herunder.
describe('parity: delt generations-kerne web ↔ mobil', () => {
  it('columnLabel er tegn-for-tegn ens (tree.ts ↔ selectors.ts)', () => {
    expect(extractFn(webTree, 'columnLabel')).toBe(extractFn(mobileSelectors, 'columnLabel'));
  });

  it('columnGen er tegn-for-tegn ens (tree.ts ↔ selectors.ts)', () => {
    expect(extractFn(webTree, 'columnGen')).toBe(extractFn(mobileSelectors, 'columnGen'));
  });

  it('buildDirection er tegn-for-tegn ens (tree.ts ↔ selectors.ts)', () => {
    expect(extractFn(webTree, 'buildDirection')).toBe(extractFn(mobileSelectors, 'buildDirection'));
  });

  it('buildBidirectionalColumns er tegn-for-tegn ens (tree.ts ↔ selectors.ts)', () => {
    expect(extractFn(webTree, 'buildBidirectionalColumns')).toBe(extractFn(mobileSelectors, 'buildBidirectionalColumns'));
  });

  it('unknownParentRing er tegn-for-tegn ens (tree.ts ↔ selectors.ts)', () => {
    expect(extractFn(webTree, 'unknownParentRing')).toBe(extractFn(mobileSelectors, 'unknownParentRing'));
  });

  it('unknownChildSection er tegn-for-tegn ens (tree.ts ↔ selectors.ts)', () => {
    expect(extractFn(webTree, 'unknownChildSection')).toBe(extractFn(mobileSelectors, 'unknownChildSection'));
  });
});

// --- Modul-niveau paritet (review 27 §2 / T2) --------------------------------------------------
// Ovenstående dækker udvalgte funktioner i generations/tree. Nedenstående dækker HELE filer for
// et bredere sæt "spejlede" moduler — ren logik der er identisk kopieret ind i både web/src/data
// og mobile/src/data, fordi der endnu ikke findes en delt npm-pakke (monorepo-ekstraktion er en
// follow-up). Formålet er at fange TAVS DRIFT: hvis nogen retter en bug eller ændrer adfærd i den
// ene kopi og glemmer den anden, skal DENNE test fejle rødt med et præcist modulnavn — ikke først
// opdages måneder senere ved manuel `diff`.
const MIRRORED_MODULES = [
  'collapseSameAs', 'relationship', 'sammeSomPreflight', 'buildModel',
];

// Nogle af filerne bærer en selv-refererende "porteret fra .../hold i sync"-kommentar, der pr.
// definition peger på den ANDEN fils sti og derfor altid vil divergere uden at det er reel
// logik-drift. Den luges ud før sammenligning. Pointer-noten kan strække sig over flere linjer
// (fx fields.ts) frem til sætningen slutter ('.'/').').
// TO vagter (review 29, Codex-fund + fields-regression):
//  1) Forbrug KUN `//`-kommentarlinjer — en ikke-kommentar (kode) afbryder straks, så
//     eksekverbar kode indsat ved pointeren aldrig slugt (ellers kunne reel drift skjules).
//  2) Stop ved pointer-sætningens slut, så en EFTERFØLGENDE separat kommentar (fx modul-doc'en
//     i fields.ts, som begge filer deler) ikke fejlagtigt fjernes fra kun den ene fil.
const POINTER_COMMENT_RE = /spejlet i |PORTERET fra /;
const SENTENCE_END_RE = /[.)]\s*$/;

function stripPointerComments(src: string): string {
  const out: string[] = [];
  let consuming = false;
  for (const line of src.split('\n')) {
    const isComment = line.trimStart().startsWith('//');
    if (consuming) {
      if (isComment) {
        if (SENTENCE_END_RE.test(line.trimEnd())) consuming = false;
        continue; // kommentar-fortsættelse af pointer-sætningen
      }
      consuming = false; // kode afbryder → slug aldrig kode
    }
    if (isComment && POINTER_COMMENT_RE.test(line)) {
      if (!SENTENCE_END_RE.test(line.trimEnd())) consuming = true;
      continue;
    }
    out.push(line);
  }
  return out.join('\n');
}

function readMirroredModule(pkg: 'web' | 'mobile', name: string): string {
  const path = join(__dirname, '../../../..', pkg, 'src/data', `${name}.ts`);
  try {
    return readFileSync(path, 'utf8');
  } catch {
    throw new Error(`parity: modulet "${name}" findes ikke i ${pkg}/src/data/ (forventet: ${path})`);
  }
}

describe('parity: spejlede data-moduler web ↔ mobil (fil-niveau)', () => {
  for (const name of MIRRORED_MODULES) {
    it(`${name} divergerer web↔mobil`, () => {
      const web = stripPointerComments(readMirroredModule('web', name));
      const mobile = stripPointerComments(readMirroredModule('mobile', name));
      expect(web).toBe(mobile);
    });
  }

  // Regressions-vagt (review 29): normaliseringen må ikke sluge eksekverbar kode indsat ved
  // en pointer-kommentar, ellers ville reel drift kunne passere som falsk grøn.
  it('normaliseringen skjuler IKKE kode-drift indsat ved en pointer-kommentar', () => {
    const base = '// PORTERET fra mobile/x — hold i sync (a;\n// b).\nexport const X = 1;\n';
    const drifted = '// PORTERET fra mobile/x — hold i sync (a;\nexport const DRIFT = true;\n// b).\nexport const X = 1;\n';
    expect(stripPointerComments(base)).not.toBe(stripPointerComments(drifted));
    // Kontrol: uden drift ER de ens (normaliseringen fjerner stadig selve pointer-kommentaren).
    expect(stripPointerComments(base)).toBe('export const X = 1;\n');
  });
});
