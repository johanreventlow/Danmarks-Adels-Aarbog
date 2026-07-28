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
    ud.push({ person_id, work: src?.titel ?? src?.udgave ?? null, side: c.side });
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
