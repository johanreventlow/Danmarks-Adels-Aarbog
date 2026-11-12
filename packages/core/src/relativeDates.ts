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

export type ReferenceStatus = 'ok' | 'mangler' | 'relativ' | 'usikker' | 'flertydig';

// Referencens dag/måned/år. Teksten kan gentage samme dato (vaerdi_tekst + date_raw) — alle forekomster skal være
// ens; to forskellige år eller datoer, en usikker eller selv relativ reference → ikke brugbar.
function parseReference(ref: string | null): Reference | Exclude<ReferenceStatus, 'ok'> {
  if (ref == null) return 'mangler';
  if (erRelativDato(ref)) return 'relativ';
  if (USIKKER.test(ref)) return 'usikker';
  const aar = new Set(ref.match(AAR) ?? []);
  if (aar.size === 0) return 'mangler';
  if (aar.size > 1) return 'flertydig';
  const datoer = new Set<string>();
  for (const m of ref.matchAll(DATO)) {
    const maaned = maanedNummer(m[2]);
    if (maaned == null) continue;
    const dag = m[1] == null ? null : Number(m[1]);
    if (dag != null && (dag < 1 || dag > 31)) return 'flertydig';
    datoer.add(JSON.stringify([dag, maaned, Number(m[3])]));
  }
  if (datoer.size > 1) return 'flertydig';
  if (datoer.size === 0) return { aar: Number([...aar][0]), maaned: null, dag: null };
  const [dag, maaned, a] = JSON.parse([...datoer][0]) as [number | null, number, number];
  return { aar: a, maaned, dag };
}

type Dato = Reference;
type Haendelse = { start: number; slut: number; del?: Del; eksplicit?: Dato };

const ensDato = (a: Dato, b: Dato) => a.aar === b.aar && a.maaned === b.maaned && a.dag === b.dag;
// Ligger `a` før `b` på det niveau, begge kender?
const foer = (a: Dato, b: Dato) => {
  if (a.aar !== b.aar) return a.aar < b.aar;
  if (a.maaned == null || b.maaned == null) return false;
  if (a.maaned !== b.maaned) return a.maaned < b.maaned;
  return a.dag != null && b.dag != null && a.dag < b.dag;
};

// Ét led opløst mod `base`: teksten, der erstatter leddet, og den dato, leddet dermed står for (dag/måned fra ordene
// lige foran: »29. s.m.«, »6. febr. s.å.«). null hvis `base` mangler den nødvendige del.
function loes(del: Del, foran: string, base: Dato): { tekst: string; dato: Dato } | null {
  const navn = base.maaned == null ? null : MAANED_NAVNE[base.maaned - 1];
  if (del === 'å') {
    const m = foran.match(/(?:(\d{1,2})\.?\s+)?(\p{L}+)\.?\s*$/u);
    const maaned = m ? maanedNummer(m[2]) : null;
    return { tekst: String(base.aar), dato: { aar: base.aar, maaned, dag: maaned != null && m?.[1] ? Number(m[1]) : null } };
  }
  if (del === 'm') {
    if (!navn) return null;
    const m = foran.match(/(\d{1,2})\.?\s*$/u);
    return { tekst: `${navn} ${base.aar}`, dato: { aar: base.aar, maaned: base.maaned, dag: m ? Number(m[1]) : null } };
  }
  if (!navn || base.dag == null) return null;
  return { tekst: `${base.dag}. ${navn} ${base.aar}`, dato: base };
}

export type OploesValg = {
  // Dåb/begravelse: et led, der opløst ligger før referencen (dåb før fødsel), er umuligt → ikke opløst.
  ikkeFoerReference?: boolean;
};

// Erstatter hvert relativt led med referencens del og bevarer resten af teksten ordret. En ikke-relativ værdi
// returneres uændret; null når et led ikke kan opløses ENTYDIGT. Bogen skriver »s.d.«/»s.m.« også i forhold til en
// dato tidligere i samme tekst (»bisat 5. april s.å. … begravet s.d.«): giver den tolkning (kæden af datoer i
// teksten) et andet resultat end referencen, er leddet flertydigt, og intet opløses.
export function oploesRelativDato(v: string, reference: string | null, valg: OploesValg = {}): string | null {
  if (!erRelativDato(v)) return v;
  const ref = parseReference(reference);
  if (typeof ref === 'string') return null;

  const h: Haendelse[] = [];
  for (const m of v.matchAll(RELATIV)) h.push({ start: m.index!, slut: m.index! + m[0].length, del: art(m[1], m[2]) });
  for (const m of v.matchAll(DATO)) {
    const maaned = maanedNummer(m[2]);
    if (maaned == null) continue;
    h.push({ start: m.index!, slut: m.index! + m[0].length,
      eksplicit: { aar: Number(m[3]), maaned, dag: m[1] == null ? null : Number(m[1]) } });
  }
  for (const m of v.matchAll(AAR)) {
    if (h.some((x) => x.eksplicit && m.index! >= x.start && m.index! < x.slut)) continue;
    h.push({ start: m.index!, slut: m.index! + m[0].length, eksplicit: { aar: Number(m[0]), maaned: null, dag: null } });
  }
  h.sort((a, b) => a.start - b.start);

  let kontekst: Dato = ref;
  const erstat: { start: number; slut: number; tekst: string }[] = [];
  for (const x of h) {
    if (x.eksplicit) { kontekst = x.eksplicit; continue; }
    const foran = v.slice(0, x.start);
    const fraRef = loes(x.del!, foran, ref);
    const fraKaede = loes(x.del!, foran, kontekst);
    if (!fraRef || !fraKaede || !ensDato(fraRef.dato, fraKaede.dato)) return null;
    if (valg.ikkeFoerReference && foer(fraRef.dato, ref)) return null;
    erstat.push({ start: x.start, slut: x.slut, tekst: fraRef.tekst });
    kontekst = fraRef.dato;
  }
  let ud = v;
  for (const e of erstat.reverse()) ud = ud.slice(0, e.start) + e.tekst + ud.slice(e.slut);
  return ud;
}

// Til målingen (tools/maal-6e1): hvorfor en reference ikke kan bruges. 'ok' betyder kun, at referencen kan læses —
// den kan stadig mangle den del, et led kræver (fx »s.m.« mod »1644«).
export function relativReferenceStatus(reference: string | null): ReferenceStatus {
  const ref = parseReference(reference);
  return typeof ref === 'string' ? ref : 'ok';
}
