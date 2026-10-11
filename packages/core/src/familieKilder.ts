// Trin 5b 2a: kilder på ægteskab og forældrelinje (spec §5.2). Familie-id'et udledes af modellens
// unions ('f' + family_id) — spousesBy bærer det ikke, og to ægteskaber med samme par er to familier.
import type { ModelIndexes } from './types';

export type FamilieKilde = {
  familyId: string;
  slags: 'aegteskab' | 'foraelder';
  counterpartPersonId: string;
  sourceRecordRef: string | null;
  sourceLabel: string;
  recordLabel: string;
  citationLabel: string;
};

const famId = (unionId: string): string | null => (unionId.startsWith('f') ? unionId.slice(1) : null);

export function familieIderForPerson(
  indexes: ModelIndexes,
  focusId: string,
): { aegteskaber: { spouseId: string | null; familyId: string }[]; foraeldreFamilie: string | null } {
  const aegteskaber: { spouseId: string | null; familyId: string }[] = [];
  for (const u of Object.values(indexes.unionById)) {
    const id = famId(u.id);
    if (!id) continue;
    if (u.p1 === focusId) aegteskaber.push({ spouseId: u.p2 ?? null, familyId: id });
    else if (u.p2 === focusId) aegteskaber.push({ spouseId: u.p1, familyId: id });
  }
  let foraeldreFamilie: string | null = null;
  const forælder = indexes.parentsByChild[focusId]?.[0];
  if (forælder) {
    for (const [unionKey, børn] of Object.entries(indexes.childrenByUnion[forælder] ?? {})) {
      if (børn.includes(focusId)) {
        foraeldreFamilie = famId(unionKey);
        break;
      }
    }
  }
  return { aegteskaber, foraeldreFamilie };
}

export function kildeLinje(k: FamilieKilde): string {
  return `Kilde: ${k.sourceLabel} · ${k.recordLabel}`;
}

// Id'er er decimalstrenge (modellens konvention, jf. web/src/data/model.ts' number | string). PostgREST
// serialiserer bigint som JSON-tal; et tal godtages kun som sikkert heltal (ellers kan JSON.parse allerede
// have afrundet det), en streng kun som decimal i Postgres-bigint-intervallet — et id uden for det ville få
// hele RPC-kaldet til at fejle. Strengsammenligning frem for BigInt: core indlæses også i mobilens runtime,
// og cifferstrenge af samme længde sammenlignes korrekt leksikografisk. Aldrig Number() på en streng.
export function bigintTekst(v: unknown): string | null {
  if (typeof v === 'number') return Number.isSafeInteger(v) ? String(v) : null;
  if (typeof v !== 'string' || !/^-?\d{1,19}$/.test(v)) return null;
  const neg = v.startsWith('-');
  const cifre = (neg ? v.slice(1) : v).replace(/^0+(?=\d)/, '');
  if (cifre.length < 19) return v;
  return cifre <= (neg ? '9223372036854775808' : '9223372036854775807') ? v : null;
}

export function mapFamilieKilder(rows: unknown): FamilieKilde[] {
  if (!Array.isArray(rows)) return [];
  const ud: FamilieKilde[] = [];
  for (const r of rows as (Record<string, unknown> | null)[]) {
    if (!r || (r.slags !== 'aegteskab' && r.slags !== 'foraelder')) continue;
    if (typeof r.source_label !== 'string' || typeof r.record_label !== 'string') continue;
    const familyId = bigintTekst(r.family_id);
    const counterpartPersonId = bigintTekst(r.counterpart_person_id);
    if (!familyId || !counterpartPersonId) continue;
    ud.push({
      familyId,
      slags: r.slags,
      counterpartPersonId,
      sourceRecordRef: typeof r.source_record_ref === 'string' ? r.source_record_ref : null,
      sourceLabel: r.source_label,
      recordLabel: r.record_label,
      citationLabel: typeof r.citation_label === 'string' ? r.citation_label : '',
    });
  }
  return ud;
}
