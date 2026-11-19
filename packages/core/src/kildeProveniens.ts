// "Kilde i Aarbogen" udledt af EVIDENSLAGET (citation → source) i stedet for af bogens egen
// nummerering (person_external_id).
//
// Hvorfor to kilder til samme visning: `person_external_id` bærer bogens nummerering
// ("Linje II, nr. 4") og findes kun for personer bogen gav et opslag. De 627 ægtefæller er
// oprettet som biprodukt af et ægteskab og har intet nummer — så `sourcesBy` var tom for dem, og
// visningen skjulte kilde-blokken helt. Proveniensen findes til gengæld for ALLE personer, fordi
// invariant 1 kræver at hvert faktum er kildebundet: fact → assertion → citation → source.
//
// Rollefordelingen er derfor: bog-nummeret er den mest præcise reference og vinder når den findes;
// citationen er reglen der dækker alle. Se `flettKilder`.
import type { SourceRef } from './types';

export type CitationProvenanceRow = {
  person_id: string | number;
  work: string | null; // source.titel ?? source.udgave
  side: string | null;
};

type RaaKilde = { titel: string | null; udgave: string | null };
export type RaaCitationRow = {
  assertion_id: number | string;
  side: string | null;
  // Trykt side (beregnet felt, findes efter DDL); til stede (også null) vinder over `side`.
  side_trykt?: string | null;
  // PostgREST returnerer et OBJEKT for en til-én-relation, men de genererede typer siger array.
  // Begge former håndteres, så apperne ikke hver især skal caste sig ud af det.
  source: RaaKilde | RaaKilde[] | null;
};

/**
 * Flader citation-rækker ud til proveniens-rækker. Assertionen bærer ikke person-id (target_id er
 * polymorf), så opslaget assertion→person leveres af kalderen. Rækker uden kendt assertion droppes.
 */
export function citationRowsTilProveniens(
  cits: RaaCitationRow[],
  personAfAssertion: Map<number | string, string>,
): CitationProvenanceRow[] {
  const ud: CitationProvenanceRow[] = [];
  for (const c of cits || []) {
    const person_id = personAfAssertion.get(c.assertion_id) ?? '';
    if (!person_id) continue;
    const src = Array.isArray(c.source) ? c.source[0] ?? null : c.source;
    ud.push({ person_id, work: src?.titel ?? src?.udgave ?? null, side: 'side_trykt' in c ? (c.side_trykt ?? null) : c.side });
  }
  return ud;
}

/** Sidetal sorteres numerisk hvor muligt, så '12' kommer før '578' (ikke leksikalsk). */
function sideNoegle(ref: string): [number, string] {
  const m = /(\d+)/.exec(ref);
  return [m ? Number(m[1]) : Number.POSITIVE_INFINITY, ref];
}

/**
 * Kilder pr. person udledt af citationer. Nøglen kanoniseres, så en samme_som-foldet person
 * samler proveniensen fra alle sine medlems-poster (fx begge udgaver).
 */
export function buildProvenanceSources(
  rows: CitationProvenanceRow[],
  canonicalIdById: Record<string, string> = {},
): Record<string, SourceRef[]> {
  const cid = (id: string) => canonicalIdById[id] ?? id;
  const perPerson = new Map<string, Map<string, SourceRef>>();
  for (const r of rows || []) {
    const work = (r.work ?? '').trim();
    if (!work) continue; // uden værk er der intet sandt at vise
    const ref = r.side ? `s. ${String(r.side).trim()}` : '';
    const key = cid(String(r.person_id));
    const set = perPerson.get(key) ?? new Map<string, SourceRef>();
    set.set(`${work}|${ref}`, { work, ref }); // dedup: fire fakta fra samme side = én kilde
    perPerson.set(key, set);
  }
  const out: Record<string, SourceRef[]> = {};
  for (const [key, set] of perPerson) {
    out[key] = [...set.values()].sort((a, b) => {
      if (a.work !== b.work) return a.work < b.work ? -1 : 1;
      const [an, at] = sideNoegle(a.ref);
      const [bn, bt] = sideNoegle(b.ref);
      return an !== bn ? an - bn : at < bt ? -1 : at > bt ? 1 : 0;
    });
  }
  return out;
}

/**
 * Bog-nummeret vinder; citationen udfylder kun hvor der ikke er noget. En tom liste tæller som
 * fraværende, og personer uden nogen af delene udelades — så visningen ikke får en tom kilde-boks.
 */
export function flettKilder(
  primaer: Record<string, SourceRef[]>,
  faldback: Record<string, SourceRef[]>,
): Record<string, SourceRef[]> {
  const out: Record<string, SourceRef[]> = {};
  for (const key of new Set([...Object.keys(primaer), ...Object.keys(faldback)])) {
    const valgt = primaer[key]?.length ? primaer[key] : faldback[key];
    if (valgt?.length) out[key] = valgt;
  }
  return out;
}

// Rækkefølgen for en persons bogreferencer (6e-2): nyeste udgave (højeste aar) først; inden for udgaven
// lavest slægtled (NULL sidst) — en person i to linjer står fuldt i linjen, hvor vedkommende er stamfar,
// mens henvisningsposten står højt i den gamle linje; dernæst laveste personId numerisk. Manglende felter
// = laveste prioritet, og lige poster beholder deres indbyrdes orden (stabil sortering).
export function sorterKilder(refs: readonly SourceRef[]): SourceRef[] {
  const num = (v: number | null | undefined, tom: number) => (v == null ? tom : v);
  const pid = (r: SourceRef) => {
    const n = r.personId == null ? NaN : Number(r.personId);
    return Number.isNaN(n) ? Number.POSITIVE_INFINITY : n;
  };
  return [...refs].sort((a, b) => {
    const aa = num(a.aar, Number.NEGATIVE_INFINITY);
    const ba = num(b.aar, Number.NEGATIVE_INFINITY);
    if (aa !== ba) return aa > ba ? -1 : 1;
    const as = num(a.slaegtled, Number.POSITIVE_INFINITY);
    const bs = num(b.slaegtled, Number.POSITIVE_INFINITY);
    if (as !== bs) return as < bs ? -1 : 1;
    const ap = pid(a);
    const bp = pid(b);
    return ap === bp ? 0 : ap < bp ? -1 : 1;
  });
}

// »Kilde i Aarbogen«s linjer uden eksakte dubletter (samme værk + ref), i den givne orden (slutreview M-6): to
// legacy-poster for samme foldede person gav ellers to ens »§ <værk>«-linjer. Kun til visningen — bogensNummer og
// optraederSom læser de urørte refs.
export function unikkeKildelinjer(refs: readonly SourceRef[]): SourceRef[] {
  const set = new Set<string>();
  return refs.filter((r) => {
    const k = `${r.work}\u0000${r.ref}`;
    if (set.has(k)) return false;
    set.add(k);
    return true;
  });
}

// Udgavens navn til læserteksterne (»DAA 1939«): udgaven, ellers værket.
const udgaveAf = (r: SourceRef): string => r.udgave ?? r.work;
// Et nummer, der kun er en side (»s. 52«, »s. 52-53«), siger ikke, hvilken bog det gælder.
const KUN_SIDE = /^s\.\s*\S+$/;

// Bogens nummer for en person (»V, nr. 1«) — KUN fra stamtavlens opslag (model.sourcesBy),
// aldrig fra citat-proveniensen, der for personer uden nummer (typisk ægtefæller) giver et sidetal.
// Én regel for personsidens etiket og feedets kilde-§, så de to aldrig viser forskellige numre.
// Er nummeret kun en side, får det udgaven foran: »DAA 1939, s. 52« (slutreview M-3).
// form 'fuld' (personsidens etiket, projektejeren 2026-11-19) giver linjens navn: »V. Den grevelige Linje af 1673,
// nr. 1« i stedet for »V, nr. 1«; samme post og orden som 'kort'.
export function bogensNummer(
  sourcesBy: Record<string, SourceRef[]> | undefined,
  personId: string,
  form: 'kort' | 'fuld' = 'kort',
): string | null {
  for (const r of sorterKilder(sourcesBy?.[personId] ?? [])) {
    const tekst = (form === 'fuld' ? r.ref : (r.kort ?? r.ref)).trim();
    if (tekst !== '') return KUN_SIDE.test(tekst) ? `${udgaveAf(r)}, ${tekst}` : tekst;
  }
  return null;
}

// »Optræder i Aarbogen som …« (spec §5.7): hver ref som »<udgave>, <kort>« (kun udgaven når kort er tom),
// i bogensNummers orden, forbundet med ' og '. Udgaven (»DAA 2018-20«) som chips, ikke værkets fulde titel (M-1).
export function optraederSom(refs: readonly SourceRef[]): string {
  const dele = sorterKilder(refs).map((r) => {
    const k = (r.kort ?? r.ref).trim();
    return k === '' ? udgaveAf(r) : `${udgaveAf(r)}, ${k}`;
  });
  return [...new Set(dele)].join(' og ');
}
