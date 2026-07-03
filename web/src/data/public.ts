// Lean offentlige læse-queries til publikums-visningerne (Godser, Våben, Om, person-detalje).
// Fejl-tolerant via safe(): logger og returnerer tomt ved manglende tabel/RLS, så visningen
// viser en tom-tilstand frem for at vælte siden — men breakage er ikke HELT tavst (console).
import { supabase } from '../supabase';
import { getAll } from './paginate';
import type { Model } from './types';
import { pickPreferredBio, type NarrativeCand } from './pickPreferredBio';

// Rå narrativ-række med source-join (PostgREST embedded resource).
type RawNarr = { id: number; subjekt_id: number | string; tekst: string | null; source_id: number | null; source: { slags: string | null; aar: number | null; udgave: string | null } | null };

async function safe<T>(fn: () => Promise<T>, fallback: T, label: string): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    console.warn(`[public] ${label} fejlede:`, e);
    return fallback;
  }
}

// Behold første forekomst pr. nøgle (rækkefølge-bevarende dedup).
function dedupBy<T>(arr: T[], key: (t: T) => string): T[] {
  const seen = new Set<string>();
  return arr.filter((t) => {
    const k = key(t);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

export type EstateItem = { id: string; navn: string; slags: string; ownerCount: number };
export type EstateOwner = { personId: string; navn: string; rolle: string; periode: string };
export type ArmsItem = { id: string; blasonering: string; note: string };
export type EstateInfo = { narrativ: string; sted: string };

type RawEstate = { id: number; navn: string | null; slags: string | null };
type RawEstateRel = { subjekt_id: number; objekt_id: number; rolle: string | null; periode_raw: string | null };

export function fetchEstates(): Promise<EstateItem[]> {
  return safe(async () => {
    const [estates, rels] = await Promise.all([
      getAll<RawEstate>(() => supabase.from('estate').select('id,navn,slags')),
      getAll<{ objekt_id: number }>(() => supabase.from('relation').select('objekt_id').eq('objekt_type', 'estate')),
    ]);
    const count: Record<string, number> = {};
    rels.forEach((r) => { count[String(r.objekt_id)] = (count[String(r.objekt_id)] ?? 0) + 1; });
    return estates
      .map((e) => ({ id: String(e.id), navn: e.navn ?? '(uden navn)', slags: e.slags ?? '', ownerCount: count[String(e.id)] ?? 0 }))
      .sort((a, b) => b.ownerCount - a.ownerCount || a.navn.localeCompare(b.navn, 'da'));
  }, [], 'fetchEstates');
}

// Ejerrækken for ét gods — navne slås op i den allerede-indlæste model (ingen ekstra person-fetch).
// En ejer-relation kan være registreret under et foldet alias-person-id, som er fjernet fra den
// collapsede model.byId → kanonisér via model.canonicalIdById før navne-opslag (ellers vises '#<id>').
export function fetchEstateOwners(estateId: string, model: Model | null): Promise<EstateOwner[]> {
  const canon = (id: string) => model?.canonicalIdById?.[id] ?? id;
  return safe(async () => {
    const rows = await getAll<RawEstateRel>(() =>
      supabase.from('relation').select('subjekt_id,objekt_id,rolle,periode_raw')
        .eq('objekt_type', 'estate').eq('objekt_id', Number(estateId)).eq('subjekt_type', 'person'));
    return rows
      .map((r) => {
        const pid = canon(String(r.subjekt_id));
        return {
          personId: pid,
          navn: model?.byId?.[pid]?.name ?? `#${r.subjekt_id}`,
          rolle: r.rolle ?? '',
          periode: r.periode_raw ?? '',
        };
      })
      .sort((a, b) => a.periode.localeCompare(b.periode, 'da'));
  }, [], 'fetchEstateOwners');
}

export function fetchArms(): Promise<ArmsItem[]> {
  return safe(async () => {
    const rows = await getAll<{ id: number; blasonering: string | null; note: string | null }>(() =>
      supabase.from('coat_of_arms').select('id,blasonering,note'));
    return rows.map((r) => ({ id: String(r.id), blasonering: r.blasonering ?? '', note: r.note ?? '' }));
  }, [], 'fetchArms');
}

// Gods-detalje: historik-narrativ (offentlig) + beliggenhed (place via sted_id). Tolerant.
export function fetchEstateInfo(estateId: string): Promise<EstateInfo> {
  return safe(async () => {
    const [narr, est] = await Promise.all([
      supabase.from('narrative').select('tekst').eq('subjekt_type', 'estate').eq('subjekt_id', Number(estateId))
        .eq('privat', false).order('id', { ascending: true }).limit(1),
      supabase.from('estate').select('sted_id').eq('id', Number(estateId)).maybeSingle(),
    ]);
    const narrativ = ((narr.data ?? [])[0] as { tekst: string | null } | undefined)?.tekst ?? '';
    let sted = '';
    const stedId = (est.data as { sted_id: number | null } | null)?.sted_id;
    if (stedId) {
      const { data: pl } = await supabase.from('place').select('navn').eq('id', stedId).maybeSingle();
      sted = (pl as { navn: string | null } | null)?.navn ?? '';
    }
    return { narrativ, sted };
  }, { narrativ: '', sted: '' }, 'fetchEstateInfo');
}

// --- Person-detalje (bio + embeder + godser) til højre-panelet ---

// Slå organisation/estate-navne op i ét hug (delt af person-detalje + relations-læsning).
export async function resolveOrgEstateNames(orgIds: number[], estIds: number[]): Promise<{ org: Map<string, string>; estate: Map<string, string> }> {
  const [orgs, ests] = await Promise.all([
    orgIds.length ? supabase.from('organisation').select('id,navn').in('id', orgIds) : Promise.resolve({ data: [] as { id: number; navn: string | null }[] }),
    estIds.length ? supabase.from('estate').select('id,navn').in('id', estIds) : Promise.resolve({ data: [] as { id: number; navn: string | null }[] }),
  ]);
  return {
    org: new Map((orgs.data ?? []).map((o) => [String(o.id), o.navn ?? ''])),
    estate: new Map((ests.data ?? []).map((e) => [String(e.id), e.navn ?? ''])),
  };
}

export type PersonOffice = { label: string; period: string };
export type PersonEstate = { id: string; navn: string };
export type PersonDetailData = { bio: string; offices: PersonOffice[]; estates: PersonEstate[] };

type RawPersonRel = { objekt_type: string; objekt_id: number; rolle: string | null; periode_raw: string | null };

// memberIds: for en samme_som-foldet person, alle medlems-id'er i gruppen — narrativ + relationer
// unioneres over dem (spec §8). Uden memberIds (ikke-foldet) = kun personens eget id.
export function fetchPersonDetail(id: string, memberIds?: string[]): Promise<PersonDetailData> {
  const empty: PersonDetailData = { bio: '', offices: [], estates: [] };
  const ids = memberIds && memberIds.length ? memberIds : [id];
  const numIds = ids.map(Number).filter((n) => !Number.isNaN(n));
  return safe(async () => {
    const [narr, rels] = await Promise.all([
      // OFFENTLIGE narrativer for alle medlems-id'er (privat filtreret i query — ikke skjult
      // bagefter, så en privat note først ikke gemmer en senere offentlig bio).
      supabase.from('narrative').select('id,subjekt_id,tekst,source_id,source:source_id(slags,aar,udgave)')
        .eq('subjekt_type', 'person').in('subjekt_id', numIds)
        .eq('privat', false).order('id', { ascending: true }),
      getAll<RawPersonRel>(() => supabase.from('relation').select('objekt_type,objekt_id,rolle,periode_raw')
        .eq('subjekt_type', 'person').in('subjekt_id', numIds).in('objekt_type', ['organisation', 'estate'])),
    ]);
    // Narrativ = union: foretrukne offentlige narrativ PR. medlem (nyeste DAA-udgave via
    // pickPreferredBio), sammenføjet. Kanonisk (id) FØRST, så den fulde founder-bio leder
    // frem for en kort kryds-reference-stub fra en alias-post. Per-medlem-valget er nu
    // deterministisk pr. udgave (ikke "første by id"); cross-medlem-concat er uændret.
    const candsByMember = new Map<string, NarrativeCand[]>();
    for (const n of (narr.data ?? []) as unknown as RawNarr[]) {
      const k = String(n.subjekt_id);
      const arr = candsByMember.get(k) ?? [];
      arr.push({ narrativeId: n.id, tekst: n.tekst, sourceId: n.source_id, slags: n.source?.slags ?? null, aar: n.source?.aar ?? null, udgave: n.source?.udgave ?? null });
      candsByMember.set(k, arr);
    }
    const firstByMember = new Map<string, string>();
    for (const [k, cands] of candsByMember) {
      const best = pickPreferredBio(cands);
      if (best?.tekst) firstByMember.set(k, best.tekst);
    }
    const orderedIds = [id, ...ids.filter((m) => m !== id)];
    const bio = [...new Set(orderedIds.map((mid) => firstByMember.get(mid)).filter(Boolean) as string[])].join('\n\n');
    const orgIds = rels.filter((r) => r.objekt_type === 'organisation').map((r) => r.objekt_id);
    const estIds = rels.filter((r) => r.objekt_type === 'estate').map((r) => r.objekt_id);
    const { org: orgNavn, estate: estNavn } = await resolveOrgEstateNames(orgIds, estIds);
    // Dedup ved union over foldede medlemmer: samme embede/gods fra to medlems-poster → én.
    const offices = dedupBy(
      rels.filter((r) => r.objekt_type === 'organisation').map((r) => ({
        label: [r.rolle, orgNavn.get(String(r.objekt_id))].filter(Boolean).join(' · ') || `#${r.objekt_id}`,
        period: r.periode_raw ?? '',
      })),
      (o) => `${o.label}|${o.period}`,
    );
    const estates = dedupBy(
      rels.filter((r) => r.objekt_type === 'estate').map((r) => ({
        id: String(r.objekt_id), navn: estNavn.get(String(r.objekt_id)) || `#${r.objekt_id}`,
      })),
      (e) => e.id,
    );
    return { bio, offices, estates };
  }, empty, 'fetchPersonDetail');
}

// Indledende narrativer på slægts-niveau (subjekt_type 'slaegt'/'lineage') til "Om slægten".
export function fetchAbout(): Promise<string[]> {
  return safe(async () => {
    const rows = await getAll<{ tekst: string | null; privat: boolean | null }>(() =>
      supabase.from('narrative').select('tekst,privat,subjekt_type').in('subjekt_type', ['slaegt', 'lineage']));
    return rows.filter((r) => !r.privat && r.tekst).map((r) => r.tekst as string);
  }, [], 'fetchAbout');
}
