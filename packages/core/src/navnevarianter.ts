// Navnefoldning til match-nøgle — KUN scoring/blocking; visningsnavne foldes ALDRIG
// (diakritik-princippet, R/tng-qa/03-normalize.R:1). Port af tværudgave-spec §3.2:
// lag 1 deterministiske grafem-regler + lag 2 kureret variant-tabel. Hver regel er
// symmetrisk, fordi begge sider af et match foldes med samme funktion.

// Titler/partikler fjernes før foldning (udvider strip_titles med Komtesse/Comtesse).
const TITLE_RE =
  /\b(lensgrevinde|lensgreve|grevinde|greve|komtesse|comtesse|baronesse|baron|friherreinde|friherre|von|af|til|de)\b/gi;

function stripTitles(s: string): string {
  return s.replace(TITLE_RE, ' ').replace(/\s+/g, ' ').trim();
}

// Lag 1 — deterministiske grafem-regler (token-vis, ordnet, konservativ).
function lag1(tok: string): string {
  let t = tok;
  t = t.replace(/th/g, 't').replace(/ph/g, 'f');        // latinisering: Cathrina, Adolph
  t = t.replace(/c(?=[aoulr])/g, 'k');                  // c→k foran a/o/u/l/r (IKKE e/i/y — Cecilie)
  t = t.replace(/w/g, 'v');                             // Wilhelm→Vilhelm
  t = t.replace(/ck/g, 'k');                            // Frederick→Frederik
  t = t.replace(/([bcdfghjklmnpqrstvxz])\1+/g, '$1');   // dobbeltkonsonant → enkelt: Detleff→Detlef
  t = t.replace(/aa/g, 'å').replace(/ö/g, 'ø').replace(/ü/g, 'y'); // gml./tysk ortografi; æ/ø/å røres aldrig
  if (t.length >= 4 && t.endsWith('a')) t = t.slice(0, -1) + 'e';  // ord-finalt a→e (Sophia, Catharina)
  return t;
}

// Lag 2 — kureret variant-tabel: ækvivalensklasser reglerne ikke kan nå. Seedet fra
// TNG-QA-fund + 1939↔2012-14-facit (Gotskalk/Gottschalk, Detlev/Detlef); udvides
// empirisk under kalibrering. Keyes på LAG-1-foldede former (foldToken folder først).
const RAW_CLASSES: string[][] = [
  ['frederik', 'friedrich', 'fritz'],
  ['henrik', 'hinrich', 'heinrich', 'henrich'],
  ['detlev', 'detlef', 'ditlev'],
  ['margrethe', 'margarethe', 'margaretha'],
  ['dorothea', 'dorthe'],
  ['cai', 'kaj', 'kay'],
  ['gotskalk', 'gottschalk', 'godskalk'],                                   // facit 1939↔2018-20
  ['cathrina', 'catharina', 'katharina', 'cathrine', 'catharine', 'katharine'], // flagship §9
];

const VARIANT_MAP: Record<string, string> = {};
for (const cls of RAW_CLASSES) {
  const repr = lag1(cls[0]);
  // repr === lag1(cls[0]) sættes af loopet nedenfor → VARIANT_MAP[repr]=repr gratis (idempotens).
  for (const m of cls) VARIANT_MAP[lag1(m)] = repr;
}

/** Fold ét navne-token til dets match-repræsentant (lag 1 grafem-regler → lag 2 variant-tabel). */
export function foldToken(token: string): string {
  const t = lag1((token ?? '').toLowerCase().trim());
  return VARIANT_MAP[t] ?? t;
}

/** Byg en persons match-nøgle: titel-/partikel-strip → tokeniser → fold hvert token. */
export function matchKey(name: string): string {
  const stripped = stripTitles((name ?? '').toLowerCase());
  return stripped
    .split(/\s+/)
    .filter(Boolean)
    .map(foldToken)
    .filter(Boolean)
    .join(' ')
    .trim();
}
