// Bygger lineage-projektionen (grene) som REN funktion — mirror af mobile/src/data/buildAux.ts's
// linje-blok, udtrukket så den kan unit-testes DB-uafhængigt. Hver person hører til én linje
// (fra person_external_id.linje); hver linje har en stamfader = medlemmet med laveste nr.
import type {
  Lineage, LineageContext, RawExtId, RawLineageContext,
  RawLineageScheme, RawLineageSchemeEntry, RawLineageSchemeEntryLineage,
} from './types';

/** Stabile nøgler for klienttilstand; den trykte kode er aldrig selv nøglen. */
export function lineageContextKey(context: LineageContext): string {
  const schemePart = context.schemeEntryId ?? context.schemeId ?? 'canonical';
  return `slaegt:${context.slaegtId}:lineage:${context.lineageId}:scheme:${schemePart}`;
}

const sourceCodeKey = (sourceId: string | number, code: string) => `${String(sourceId)}:${code}`;

export type LineageSchemeRows = {
  schemes: RawLineageScheme[];
  entries: RawLineageSchemeEntry[];
  mappings: RawLineageSchemeEntryLineage[];
};

export function buildLineage(
  extIds: RawExtId[],
  lineageRows: RawLineageContext[],
  // samme_som-collapse: person-id'er kanoniseres, så en foldet grundlægger hører til flere linjer
  // (spec §8). Default {} for bagudkompat i eksisterende tests.
  canonicalIdById: Record<string, string> = {},
  schemeRows?: LineageSchemeRows,
): Lineage {
  const cid = (id: string) => canonicalIdById[id] ?? id;
  const byPerson: Record<string, string[]> = {};
  const counts: Record<string, number> = {};
  const head: Record<string, { id: string; nr: number }> = {};

  const rowsBySourceCode = new Map<string, RawLineageContext>();
  const rowsById = new Map<string, RawLineageContext>();
  const clansByCode = new Map<string, Set<string>>();
  (lineageRows || []).forEach((row) => {
    if (!row.kode) return;
    rowsBySourceCode.set(sourceCodeKey(row.source_id, row.kode), row);
    if (row.id != null) rowsById.set(String(row.id), row);
    if (row.slaegt_id != null) {
      const clans = clansByCode.get(row.kode) ?? new Set<string>();
      clans.add(String(row.slaegt_id));
      clansByCode.set(row.kode, clans);
    }
  });
  // Gamle baser uden Task 6-kontekst læser fortsat rå koder. Så snart der er
  // kontekst i svaret, bliver også legacy-rækker source-scopede frem for globale.
  const hasContext = (lineageRows || []).some((row) => row.id != null && row.slaegt_id != null);
  const schemeById = new Map((schemeRows?.schemes ?? []).map((scheme) => [String(scheme.id), scheme]));
  const entryBySourceCode = new Map<string, RawLineageSchemeEntry>();
  (schemeRows?.entries ?? []).forEach((entry) => {
    const scheme = schemeById.get(String(entry.scheme_id));
    // person_external_id.linje er stamtavlens koordinat — aldrig et præsens- eller
    // redaktionelt nummer, selv hvis de deler kode inden for den samme kilde.
    if (scheme?.kind === 'stamtavle' && scheme.source_id != null) {
      entryBySourceCode.set(sourceCodeKey(scheme.source_id, entry.code), entry);
    }
  });
  const canonicalLineagesByEntry = new Map<string, Set<string>>();
  const unresolvedCoordinates = new Set<string>();
  (schemeRows?.mappings ?? []).forEach((mapping) => {
    if (mapping.relation_kind !== 'canonical') return;
    const entryId = String(mapping.entry_id);
    const lineages = canonicalLineagesByEntry.get(entryId) ?? new Set<string>();
    lineages.add(String(mapping.lineage_id));
    canonicalLineagesByEntry.set(entryId, lineages);
  });
  const keyFor = (sourceId: string | number, code: string): string => {
    const row = rowsBySourceCode.get(sourceCodeKey(sourceId, code));
    const entry = entryBySourceCode.get(sourceCodeKey(sourceId, code));
    const scheme = entry ? schemeById.get(String(entry.scheme_id)) : undefined;
    const mappedLineages = entry ? canonicalLineagesByEntry.get(String(entry.id)) : undefined;
    const mappedLineageId = mappedLineages?.size === 1 ? [...mappedLineages][0] : undefined;
    if (entry && scheme && mappedLineageId) {
      return lineageContextKey({
        slaegtId: String(scheme.slaegt_id), lineageId: mappedLineageId,
        schemeId: String(scheme.id), schemeEntryId: String(entry.id),
      });
    }
    if (row?.id != null && row.slaegt_id != null) {
      return lineageContextKey({ slaegtId: String(row.slaegt_id), lineageId: String(row.id) });
    }
    const coordinate = sourceCodeKey(sourceId, code);
    if (hasContext && !unresolvedCoordinates.has(coordinate)) {
      unresolvedCoordinates.add(coordinate);
      console.warn('[lineage] uafklaret legacy-kildekoordinat — bruger ikke scheme-entry:', coordinate);
    }
    return hasContext ? `legacy-source:${sourceCodeKey(sourceId, code)}` : code;
  };

  (extIds || []).forEach((x) => {
    if (!x.linje) return;
    const pid = cid(String(x.person_id));
    const key = keyFor(x.source_id, x.linje);
    const arr = (byPerson[pid] ??= []);
    // Tæl distinkte kanoniske personer pr. linje (ikke ext-rækker).
    if (!arr.includes(key)) {
      arr.push(key);
      counts[key] = (counts[key] || 0) + 1;
    }
    const nr = x.nr == null ? 9999 : x.nr;
    const cur = head[key];
    if (!cur || nr < cur.nr) head[key] = { id: pid, nr };
  });

  // Linje-navne fra lineage-tabellen (kode → navn); fallback til kode hvis tom/mangler.
  const navn: Record<string, string> = {};
  (lineageRows || []).forEach((l) => {
    if (!l.kode) return;
    const key = keyFor(l.source_id, l.kode);
    const base = l.canonical_label ?? l.navn;
    if (!base) return;
    navn[key] = (clansByCode.get(l.kode)?.size ?? 0) > 1 && l.slaegtsnavn
      ? `${l.slaegtsnavn} · ${base}`
      : base;
  });
  // Et source scheme kan bruge en anden kode end lineage.source_id/kode (fx 1939 II
  // og 2018–20 V). Labelen kommer derfor fra den mapped kanoniske lineage, med
  // scheme-entryens trykte label som eksplicit fallback.
  (schemeRows?.entries ?? []).forEach((entry) => {
    const scheme = schemeById.get(String(entry.scheme_id));
    const mappedLineages = canonicalLineagesByEntry.get(String(entry.id));
    const lineageId = mappedLineages?.size === 1 ? [...mappedLineages][0] : undefined;
    if (!scheme || scheme.kind !== 'stamtavle' || scheme.source_id == null || !lineageId) return;
    const row = rowsById.get(lineageId);
    const key = lineageContextKey({
      slaegtId: String(scheme.slaegt_id), lineageId,
      schemeId: String(scheme.id), schemeEntryId: String(entry.id),
    });
    const base = row?.canonical_label ?? row?.navn ?? entry.label;
    navn[key] = row?.slaegtsnavn && (clansByCode.get(entry.code)?.size ?? 0) > 1
      ? `${row.slaegtsnavn} · ${base}`
      : base;
  });

  const list = Object.keys(counts)
    .sort()
    .map((l) => ({ linje: l, count: counts[l], headId: head[l]?.id ?? null, navn: navn[l] ?? null }));

  return { byPerson, list, navn };
}
