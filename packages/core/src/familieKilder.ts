// Trin 5b 2a: kilder på ægteskab og forældrelinje (spec §5.2); 2b-iii: børneflokken (slags 'boern'). Familie-id'et udledes af modellens
// unions ('f' + family_id) — spousesBy bærer det ikke, og to ægteskaber med samme par er to familier.
import type { ModelIndexes } from './types';
import { visbarPostEtiket } from './recordLabel';

export type FamilieKilde = {
  familyId: string;
  slags: 'aegteskab' | 'foraelder' | 'boern';
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
): { aegteskaber: { spouseId: string | null; familyId: string }[]; foraeldreFamilier: string[]; boerneFamilier: string[] } {
  const aegteskaber: { spouseId: string | null; familyId: string }[] = [];
  // Trin 5b 2b-iii: familier, hvor fokuspersonen er partner og har børn (børneflokkens kilde vises dér).
  const boerneFamilier = new Set<string>();
  for (const u of Object.values(indexes.unionById)) {
    const id = famId(u.id);
    if (!id) continue;
    if (u.p1 === focusId) aegteskaber.push({ spouseId: u.p2 ?? null, familyId: id });
    else if (u.p2 === focusId) aegteskaber.push({ spouseId: u.p1, familyId: id });
    if ((u.p1 === focusId || u.p2 === focusId) && (indexes.childrenByUnion[focusId]?.[u.id]?.length ?? 0) > 0) boerneFamilier.add(id);
  }
  // Fødselsfamilierne for de forældre, modellen viser (buildModel tager kun barnets første familie med i
  // parentsByChild); en kilde vises aldrig ved en forælder, panelet ikke viser.
  const foraeldreFamilier = new Set<string>();
  for (const forælder of indexes.parentsByChild[focusId] ?? []) {
    for (const [unionKey, børn] of Object.entries(indexes.childrenByUnion[forælder] ?? {})) {
      const id = famId(unionKey);
      if (id && børn.includes(focusId)) foraeldreFamilier.add(id);
    }
  }
  return { aegteskaber, foraeldreFamilier: [...foraeldreFamilier].sort(), boerneFamilier: [...boerneFamilier].sort() };
}

// Trin 6d-3 spor L: kildefiltrene til detaljepanelet. Bindingens modpart er postens eget person-id (fx 1939's
// alias-række), mens modellen efter samme_som-sammenfoldningen viser kanoniske id'er; modparten slås derfor op
// kanonisk (canon[id] ?? id). Familien skal stadig være én af de viste — et kanonisk match alene giver ingen kilde.
export type FamilieIder = ReturnType<typeof familieIderForPerson>;
const kanonisk = (canon: Record<string, string>, id: string): string => canon[id] ?? id;

// Ægteskabskilder for én ægtefælle: familien skal være deres fælles, og modparten ægtefællen eller personen selv.
export function aegteskabsKilder(kilder: FamilieKilde[], ider: FamilieIder, spouseId: string | null, focusId: string,
  canon: Record<string, string>): FamilieKilde[] {
  const fam = new Set(ider.aegteskaber.filter((a) => a.spouseId === spouseId).map((a) => a.familyId));
  return kilder.filter((k) => {
    if (k.slags !== 'aegteskab' || !fam.has(k.familyId)) return false;
    const mod = kanonisk(canon, k.counterpartPersonId);
    return mod === spouseId || mod === focusId;
  });
}

// Forælderkilden hører kun til den forælder, påstanden handler om (aldrig ved begge; spec 5b §5.2). 2b-iii: en
// børnekilde fra forælderens post vises hos barnet på samme måde (modparten er forælderen).
export function foraelderKilder(kilder: FamilieKilde[], ider: FamilieIder, parentId: string,
  canon: Record<string, string>): FamilieKilde[] {
  return kilder.filter((k) => (k.slags === 'foraelder' || k.slags === 'boern')
    && ider.foraeldreFamilier.includes(k.familyId) && kanonisk(canon, k.counterpartPersonId) === parentId);
}

// Trin 5b 2b-iii: børneflokkens kilde hos forælderen (modparten er forælderen selv).
export function boerneKilder(kilder: FamilieKilde[], ider: FamilieIder, focusId: string,
  canon: Record<string, string>): FamilieKilde[] {
  return kilder.filter((k) => k.slags === 'boern'
    && ider.boerneFamilier.includes(k.familyId) && kanonisk(canon, k.counterpartPersonId) === focusId);
}

export function kildeLinje(k: FamilieKilde): string {
  const post = visbarPostEtiket(k.recordLabel);
  return post ? `Kilde: ${k.sourceLabel} · ${post}` : `Kilde: ${k.sourceLabel}`;
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
    if (!r || (r.slags !== 'aegteskab' && r.slags !== 'foraelder' && r.slags !== 'boern')) continue;
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
