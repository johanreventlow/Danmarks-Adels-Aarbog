// Rene generations-helpers. Coalescer ALDRIG generation pr. person: en founder bærer flere
// linje-koordinater med hver sit tal (en person kan være III/12 OG V/1). Koordinaterne driver
// slægtled-labels på det beviste træ (columnGen i tree.ts/selectors.ts) OG den marker-gatede
// kandidat-visning (unknownParentRing) — begge læser den FAKTISKE koordinat, aldrig aritmetik.
import type { RawExtId, RawLineage } from './types';

export type GenCoord = {
  sourceId: string;
  linje: string;
  lineageId: string | null;
  parentLineageId: string | null;
  lokal: number | null;
  gennem: number | null;
  kuld: string | null;
};

// Marker-gatet "forældre ukendt": grad = kildens præcise udsagn (assertionens vaerdi_tekst),
// kilde = proveniens (citationens citat_tekst, fx 'DAA 1939 s.97'). Grad-værdierne er
// GRADE_FORAELDER_UKENDT ('forælder findes, men ukendt for os') og GRADE_INGEN_FORBINDELSE
// ('bogen forbinder slet ikke personen opad') — se docs/reviews/25-*.
export const GRADE_FORAELDER_UKENDT = 'forælder ukendt';
export const GRADE_INGEN_FORBINDELSE = 'ingen forbindelse angivet';

export type ParentsUnknown = { grade: string; kilde: string | null };

// Ren resolver: fold facts (faktatype='forældre_ukendt') + AFKLAREDE konklusioner + valgt
// assertion (grad) + citation (proveniens) til ét opslag pr. kanonisk person. En markering tæller
// KUN når den har en afklaret konklusion (ellers er den en ubesluttet kandidat, ikke en gate).
export function buildParentsUnknown(
  facts: { id: string | number; subjekt_id: string | number }[],
  conclusions: { target_id: string | number; valgt_assertion_id: string | number | null }[],
  assertions: { id: string | number; vaerdi_tekst: string | null }[],
  citations: { assertion_id: string | number; citat_tekst: string | null }[],
  canonicalIdById: Record<string, string>,
): Record<string, ParentsUnknown> {
  const chosenByFact = new Map<string, string>();
  for (const c of conclusions) {
    if (c.valgt_assertion_id != null) chosenByFact.set(String(c.target_id), String(c.valgt_assertion_id));
  }
  const gradeByAssertion = new Map<string, string | null>();
  for (const a of assertions) gradeByAssertion.set(String(a.id), a.vaerdi_tekst);
  const kildeByAssertion = new Map<string, string | null>();
  for (const ct of citations) {
    if (!kildeByAssertion.has(String(ct.assertion_id))) kildeByAssertion.set(String(ct.assertion_id), ct.citat_tekst);
  }
  const out: Record<string, ParentsUnknown> = {};
  for (const f of facts) {
    const aid = chosenByFact.get(String(f.id));
    if (aid == null) continue; // ingen afklaret konklusion → ikke en aktiv markering
    const canon = canonicalIdById[String(f.subjekt_id)] ?? String(f.subjekt_id);
    if (out[canon]) continue; // første afklarede markering pr. person vinder (deterministisk)
    out[canon] = { grade: gradeByAssertion.get(aid) ?? '', kilde: kildeByAssertion.get(aid) ?? null };
  }
  return out;
}

export function buildGenCoords(
  extIds: RawExtId[],
  lineageRows: RawLineage[],
  canonicalIdById: Record<string, string>,
): Record<string, GenCoord[]> {
  const linById = new Map<string, RawLineage>();
  for (const l of lineageRows) linById.set(`${l.source_id}:${l.kode}`, l);
  const out: Record<string, GenCoord[]> = {};
  for (const x of extIds) {
    if (x.linje == null) continue; // NULL linje karantænes — ingen koordinat
    const canon = canonicalIdById[String(x.person_id)] ?? String(x.person_id);
    const lin = linById.get(`${x.source_id}:${x.linje}`) ?? null;
    (out[canon] ??= []).push({
      sourceId: String(x.source_id),
      linje: x.linje,
      lineageId: lin && lin.id != null ? String(lin.id) : null,
      parentLineageId: lin && lin.parent_lineage_id != null ? String(lin.parent_lineage_id) : null,
      lokal: x.slaegtled_lokal ?? null,
      gennem: x.slaegtled_gennem ?? null,
      kuld: x.kuld ?? null,
    });
  }
  return out;
}
