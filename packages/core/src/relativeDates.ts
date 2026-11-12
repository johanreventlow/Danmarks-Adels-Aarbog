// Relative datoer i DAA (6e-1, spec 2026-11-12-trin6e-laeserflade-design.md §5.4a, afgørelse 12): »29. s.m.«
// (samme måned), »6. febr. s.å.« (samme år), »s.d.« (samme dag); 1939's OCR skriver fx »15 s. M.« og »s. A.«.
// Uden for bogens sammenhæng er de meningsløse, så læseren opløser dem ud fra en reference (dåb ← fødsel,
// begravelse ← død; se editionFacts.ts). Konservativt: kan referencen ikke give den nødvendige del entydigt og
// sikkert, opløses intet (null), og bogens tekst vises.
import { maanedNummer } from './factEquality';

// »s.m.«, »s. M.«, »s.å.«, »s.a.«, »s. A.«, »s.d.«, »s. D.« og »samme dag/måned/maaned/år/aar«. Kræver at »s« ikke
// står inde i et ord, og at bogstavet ikke fortsætter et ord (»s.st.«, »s. Andersen« er ikke relative).
const RELATIV = /(?<![\p{L}\p{N}])(?:s\.\s*([mdåa])\.?|samme\s+(dag|måned|maaned|år|aar))(?!\p{L})/giu;

const MAANED_NAVNE = ['januar', 'februar', 'marts', 'april', 'maj', 'juni', 'juli', 'august', 'september', 'oktober',
  'november', 'december'];

// Usikre eller flertydige referencer (mit valg): en sikker dato må ikke udledes af »ca. 1644«, »1644?«, »før 1644«,
// »1643 eller 1644« eller et interval (»21.-22. april«).
const USIKKER = /\?|(?<![\p{L}])(?:ca|circa|o|omkr|før|efter|mellem|eller|el|senest|tidligst|formentlig|antagelig|vistnok)(?![\p{L}])|\d\.?\s*[-–]\s*\d/iu;

const DATO = /(?<![\p{L}\p{N}])(?:(\d{1,2})\.?\s+)?(\p{L}+)\.?\s+(\d{4})(?!\d)/gu;
const AAR = /(?<!\d)\d{4}(?!\d)/g;

type Del = 'm' | 'd' | 'å';
type Reference = { aar: number; maaned: number | null; dag: number | null };

const art = (bogstav: string | undefined, ord: string | undefined): Del => {
  const b = (bogstav ?? ord ?? '').toLowerCase();
  return b.startsWith('m') ? 'm' : b.startsWith('d') ? 'd' : 'å';
};

export function erRelativDato(v: string): boolean {
  RELATIV.lastIndex = 0;
  const hit = RELATIV.test(v);
  RELATIV.lastIndex = 0;
  return hit;
}

// Referencens dag/måned/år. Teksten kan gentage samme dato (vaerdi_tekst + date_raw) — alle forekomster skal være
// ens; to forskellige år eller datoer, en usikker eller selv relativ reference → null.
function parseReference(ref: string | null): Reference | null {
  if (ref == null || erRelativDato(ref) || USIKKER.test(ref)) return null;
  const aar = new Set(ref.match(AAR) ?? []);
  if (aar.size !== 1) return null;
  const datoer = new Set<string>();
  for (const m of ref.matchAll(DATO)) {
    const maaned = maanedNummer(m[2]);
    if (maaned == null) continue;
    const dag = m[1] == null ? null : Number(m[1]);
    if (dag != null && (dag < 1 || dag > 31)) return null;
    datoer.add(JSON.stringify([dag, maaned, Number(m[3])]));
  }
  if (datoer.size > 1) return null;
  if (datoer.size === 0) return { aar: Number([...aar][0]), maaned: null, dag: null };
  const [dag, maaned, a] = JSON.parse([...datoer][0]) as [number | null, number, number];
  return { aar: a, maaned, dag };
}

// Erstatter hvert relativt led med referencens del og bevarer resten af teksten ordret. En ikke-relativ værdi
// returneres uændret; null når et led ikke kan opløses.
export function oploesRelativDato(v: string, reference: string | null): string | null {
  if (!erRelativDato(v)) return v;
  const ref = parseReference(reference);
  if (!ref) return null;
  let fejl = false;
  const ud = v.replace(RELATIV, (_hel, bogstav: string | undefined, ord: string | undefined) => {
    const del = art(bogstav, ord);
    const maaned = ref.maaned == null ? null : MAANED_NAVNE[ref.maaned - 1];
    if (del === 'å') return String(ref.aar);
    if (del === 'm' && maaned) return `${maaned} ${ref.aar}`;
    if (del === 'd' && maaned && ref.dag != null) return `${ref.dag}. ${maaned} ${ref.aar}`;
    fejl = true;
    return _hel;
  });
  return fejl ? null : ud;
}
