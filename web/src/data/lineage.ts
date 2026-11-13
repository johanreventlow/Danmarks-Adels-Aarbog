// Bygger lineage-projektionen (grene) som REN funktion — mirror af mobile/src/data/buildAux.ts's
// linje-blok, udtrukket så den kan unit-testes DB-uafhængigt. Hver person hører til én linje
// (fra person_external_id.linje); hver linje har en stamfader = medlemmet med laveste nr.
import type {
  Lineage, LineageContext, RawExtId, RawLineageContext,
  RawLineageScheme, RawLineageSchemeEntry, RawLineageSchemeEntryLineage,
} from './types';
import { compareLineHead, type SkemaOpslag } from '@daa/core';

/** Stabile nøgler for klienttilstand; den trykte kode er aldrig selv nøglen. */
export function lineageContextKey(context: LineageContext): string {
  const schemePart = context.schemeEntryId ?? context.schemeId ?? 'canonical';
  return `slaegt:${context.slaegtId}:lineage:${context.lineageId}:scheme:${schemePart}`;
}

const sourceCodeKey = (sourceId: string | number, code: string) => `${String(sourceId)}:${code}`;

// Tekniske linjenøgler (en uafklaret legacy-kildekoordinat, se keyFor nedenfor) vises aldrig i læseren — hverken i
// persondetaljens linjemærker eller i søge-/kortfladens linjechips (spec §5.7, final review C7).
export const erTekniskLinje = (key: string): boolean => key.startsWith('legacy-source:');
export const synligeLinjer = <T extends { linje: string }>(list: readonly T[]): T[] => list.filter((l) => !erTekniskLinje(l.linje));

export type LineageSchemeRows = {
  schemes: RawLineageScheme[];
  entries: RawLineageSchemeEntry[];
  mappings: RawLineageSchemeEntryLineage[];
};

/**
 * Stamtavlens skemaindgange pr. (kilde, kode) — person_external_id.linje er stamtavlens koordinat, aldrig et
 * præsens- eller redaktionelt nummer, selv hvis de deler kode inden for samme kilde. Delt af buildLineage og
 * kildeetiketterne (stamtavleSkemaOpslag).
 */
export function stamtavleEntries(schemeRows?: LineageSchemeRows): Map<string, RawLineageSchemeEntry> {
  const schemeById = new Map((schemeRows?.schemes ?? []).map((scheme) => [String(scheme.id), scheme]));
  const out = new Map<string, RawLineageSchemeEntry>();
  (schemeRows?.entries ?? []).forEach((entry) => {
    const scheme = schemeById.get(String(entry.scheme_id));
    if (scheme?.kind === 'stamtavle' && scheme.source_id != null) {
      out.set(sourceCodeKey(scheme.source_id, entry.code), entry);
    }
  });
  return out;
}

export function stamtavleSkemaOpslag(schemeRows?: LineageSchemeRows): SkemaOpslag {
  const m = stamtavleEntries(schemeRows);
  const kilderMedSkema = new Set([...m.keys()].map((k) => k.slice(0, k.indexOf(':'))));
  return (sourceId, code) => {
    if (!kilderMedSkema.has(String(sourceId))) return undefined;
    const e = m.get(sourceCodeKey(sourceId, code));
    return e ? { code: e.code, label: e.label } : null;
  };
}

export function buildLineage(
  extIds: RawExtId[],
  lineageRows: RawLineageContext[],
  // samme_som-collapse: person-id'er kanoniseres, så en foldet grundlægger hører til flere linjer
  // (spec §8). Default {} for bagudkompat i eksisterende tests.
  canonicalIdById: Record<string, string> = {},
  schemeRows?: LineageSchemeRows,
  // 6e-2 slutreview I-1: udgavernes årstal (source.aar) — listens stamfader tages fra den nyeste udgave med rækker i
  // linjen. Uden: alle udgaver er lige gamle, og stamfaderen er den bedste på tværs af dem.
  sources?: ReadonlyArray<{ id: number | string; aar?: number | null }>,
): Lineage {
  const cid = (id: string) => canonicalIdById[id] ?? id;
  const byPerson: Record<string, string[]> = {};
  type Hoved = { id: string; nr: number | null; nr_label: string | null; slaegtled: number | null };
  // Per-udgave-nøgle → kanonisk linjenøgle (slægt + lineage, uden skemadel). Kun nøgler med lineage-kontekst; en rå kode
  // (base uden kontekst) er sin egen kanoniske nøgle, og en teknisk nøgle har ingen.
  const kanonisk: Record<string, string> = {};

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
  const entryBySourceCode = stamtavleEntries(schemeRows);
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
      const key = lineageContextKey({
        slaegtId: String(scheme.slaegt_id), lineageId: mappedLineageId,
        schemeId: String(scheme.id), schemeEntryId: String(entry.id),
      });
      kanonisk[key] = lineageContextKey({ slaegtId: String(scheme.slaegt_id), lineageId: mappedLineageId });
      return key;
    }
    if (row?.id != null && row.slaegt_id != null) {
      const key = lineageContextKey({ slaegtId: String(row.slaegt_id), lineageId: String(row.id) });
      kanonisk[key] = key;
      return key;
    }
    const coordinate = sourceCodeKey(sourceId, code);
    if (hasContext && !unresolvedCoordinates.has(coordinate)) {
      unresolvedCoordinates.add(coordinate);
      console.warn('[lineage] uafklaret legacy-kildekoordinat — bruger ikke scheme-entry:', coordinate);
    }
    return hasContext ? `legacy-source:${sourceCodeKey(sourceId, code)}` : code;
  };

  // Listefladerne (slutreview I-1): én post pr. kanonisk linje på tværs af udgaver. Antal = distinkte kanoniske personer
  // i alle udgaver; stamfader pr. (linje, udgave), valgt fra den nyeste udgave nedenfor.
  const medlemmer = new Map<string, Set<string>>();
  const hovedPrUdgave = new Map<string, Map<string, Hoved>>();
  const kanoniskAf = (key: string): string | null => (erTekniskLinje(key) ? null : kanonisk[key] ?? key);
  (extIds || []).forEach((x) => {
    if (!x.linje) return;
    const pid = cid(String(x.person_id));
    const key = keyFor(x.source_id, x.linje);
    const arr = (byPerson[pid] ??= []);
    if (!arr.includes(key)) arr.push(key);
    const kn = kanoniskAf(key);
    if (kn == null) return;
    const s = medlemmer.get(kn) ?? new Set<string>();
    s.add(pid);
    medlemmer.set(kn, s);
    // Linjens hoved (6e-2): laveste slægtled, så unummereret før nummereret, så trykt nr.; suffikset afgør (15a før 15b).
    // Har en udgave flere skemaindgange i samme linje, er hovedet det bedste på tværs af dem (samme regel).
    const kand: Hoved = { id: pid, nr: x.nr ?? null, nr_label: x.nr_label ?? null, slaegtled: x.slaegtled_lokal ?? null };
    const prUdgave = hovedPrUdgave.get(kn) ?? new Map<string, Hoved>();
    const cur = prUdgave.get(String(x.source_id));
    if (!cur || compareLineHead(kand, cur) < 0) prUdgave.set(String(x.source_id), kand);
    hovedPrUdgave.set(kn, prUdgave);
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

  // Stamfaderen kommer fra den nyeste udgave (højeste aar; ukendt aar = ældst) med rækker i linjen. Lige gamle udgaver:
  // det bedste hoved på tværs af dem.
  const aarAf = new Map((sources ?? []).map((src) => [String(src.id), src.aar ?? null]));
  const aar = (sid: string) => aarAf.get(sid) ?? Number.NEGATIVE_INFINITY;
  const hovedFor = (kn: string): Hoved | null => {
    let bedst: { aar: number; h: Hoved } | null = null;
    for (const [sid, h] of hovedPrUdgave.get(kn) ?? []) {
      const a = aar(sid);
      if (!bedst || a > bedst.aar || (a === bedst.aar && compareLineHead(h, bedst.h) < 0)) bedst = { aar: a, h };
    }
    return bedst?.h ?? null;
  };
  // Den kanoniske nøgles navn: navnet på en af dens udgavenøgler (de deler lineage og dermed kanonisk navn).
  for (const key of Object.keys(kanonisk).sort()) {
    const kn = kanonisk[key];
    if (navn[kn] == null && navn[key] != null) navn[kn] = navn[key];
  }

  const list = [...medlemmer.keys()]
    .sort()
    .map((l) => ({ linje: l, count: medlemmer.get(l)!.size, headId: hovedFor(l)?.id ?? null, navn: navn[l] ?? null }));

  return { byPerson, list, navn, kanonisk };
}

// Listefladernes linjer for en person (slutreview I-1): kanoniske nøgler (list[].linje), uden tekniske, i byPersons
// orden. Uden kanonisk afbildning (ældre producent) er nøglerne byPersons egne.
export function kanoniskeLinjer(lineage: Lineage | null | undefined, personId: string): string[] {
  const ud: string[] = [];
  for (const k of lineage?.byPerson[personId] ?? []) {
    if (erTekniskLinje(k)) continue;
    const kn = lineage?.kanonisk?.[k] ?? k;
    if (!ud.includes(kn)) ud.push(kn);
  }
  return ud;
}

// Hele afbildningen person → kanoniske linjer, til filtre der tager et opslag (buildBrowse, filterByLineage).
export function kanoniskeLinjerPrPerson(lineage: Lineage | null | undefined): Record<string, string[]> {
  const ud: Record<string, string[]> = {};
  for (const pid of Object.keys(lineage?.byPerson ?? {})) ud[pid] = kanoniskeLinjer(lineage, pid);
  return ud;
}

// En linjenøgle fra en liste eller en URL gjort kanonisk: en ældre per-udgave-nøgle (delte søgelinks fra før I-1)
// filtrerer som sin kanoniske linje.
export const kanoniskLinje = (lineage: Lineage | null | undefined, key: string): string => lineage?.kanonisk?.[key] ?? key;
