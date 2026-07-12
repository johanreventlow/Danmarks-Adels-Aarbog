// Mekanisk paritets-test: håndhæver at den delte generations-kerne forbliver tegn-for-tegn ens
// mellem web og mobil. Indtil nu blev det kun tjekket manuelt med `diff` — denne test fejler CI
// hvis en af de fire funktioner drifter mellem platformene (design-spec T5).
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const mobileGenerations = readFileSync(join(__dirname, '../generations.ts'), 'utf8');
const webGenerations = readFileSync(
  join(__dirname, '../../../../web/src/data/generations.ts'),
  'utf8',
);
const mobileSelectors = readFileSync(join(__dirname, '../selectors.ts'), 'utf8');
const webTree = readFileSync(join(__dirname, '../../../../web/src/data/tree.ts'), 'utf8');

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

describe('parity: delt generations-kerne web ↔ mobil', () => {
  it('buildGenCoords er tegn-for-tegn ens (generations.ts)', () => {
    expect(extractFn(mobileGenerations, 'buildGenCoords')).toBe(extractFn(webGenerations, 'buildGenCoords'));
  });

  it('buildParentsUnknown er tegn-for-tegn ens (generations.ts)', () => {
    expect(extractFn(mobileGenerations, 'buildParentsUnknown')).toBe(extractFn(webGenerations, 'buildParentsUnknown'));
  });

  it('columnLabel er tegn-for-tegn ens (selectors.ts ↔ tree.ts)', () => {
    expect(extractFn(mobileSelectors, 'columnLabel')).toBe(extractFn(webTree, 'columnLabel'));
  });

  it('columnGen er tegn-for-tegn ens (selectors.ts ↔ tree.ts)', () => {
    expect(extractFn(mobileSelectors, 'columnGen')).toBe(extractFn(webTree, 'columnGen'));
  });

  it('buildDirection er tegn-for-tegn ens (selectors.ts ↔ tree.ts)', () => {
    expect(extractFn(mobileSelectors, 'buildDirection')).toBe(extractFn(webTree, 'buildDirection'));
  });

  it('buildBidirectionalColumns er tegn-for-tegn ens (selectors.ts ↔ tree.ts)', () => {
    expect(extractFn(mobileSelectors, 'buildBidirectionalColumns')).toBe(extractFn(webTree, 'buildBidirectionalColumns'));
  });

  it('unknownParentRing er tegn-for-tegn ens (selectors.ts ↔ tree.ts)', () => {
    expect(extractFn(mobileSelectors, 'unknownParentRing')).toBe(extractFn(webTree, 'unknownParentRing'));
  });

  it('unknownChildSection er tegn-for-tegn ens (selectors.ts ↔ tree.ts)', () => {
    expect(extractFn(mobileSelectors, 'unknownChildSection')).toBe(extractFn(webTree, 'unknownChildSection'));
  });
});
