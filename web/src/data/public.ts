// Lean offentlige læse-queries til publikums-visningerne (Godser, Våben, Om slægten).
// Tolerant: returnerer tomt ved fejl (manglende tabel/RLS) → visningen viser en tom-tilstand
// frem for at vælte hele siden.
import { supabase } from '../supabase';
import { getAll } from './paginate';
import type { Model } from './types';

export type EstateItem = { id: string; navn: string; slags: string; ownerCount: number };
export type EstateOwner = { personId: string; navn: string; rolle: string; periode: string };
export type ArmsItem = { id: string; blasonering: string };

type RawEstate = { id: number; navn: string | null; slags: string | null };
type RawEstateRel = { subjekt_id: number; objekt_id: number; rolle: string | null; periode_raw: string | null };

export async function fetchEstates(): Promise<EstateItem[]> {
  try {
    const [estates, rels] = await Promise.all([
      getAll<RawEstate>(() => supabase.from('estate').select('id,navn,slags')),
      getAll<{ objekt_id: number }>(() => supabase.from('relation').select('objekt_id').eq('objekt_type', 'estate')),
    ]);
    const count: Record<string, number> = {};
    rels.forEach((r) => { count[String(r.objekt_id)] = (count[String(r.objekt_id)] ?? 0) + 1; });
    return estates
      .map((e) => ({ id: String(e.id), navn: e.navn ?? '(uden navn)', slags: e.slags ?? '', ownerCount: count[String(e.id)] ?? 0 }))
      .sort((a, b) => b.ownerCount - a.ownerCount || a.navn.localeCompare(b.navn, 'da'));
  } catch {
    return [];
  }
}

// Ejerrækken for ét gods — navne slås op i den allerede-indlæste model (ingen ekstra person-fetch).
export async function fetchEstateOwners(estateId: string, model: Model | null): Promise<EstateOwner[]> {
  try {
    const rows = await getAll<RawEstateRel>(() =>
      supabase.from('relation').select('subjekt_id,objekt_id,rolle,periode_raw')
        .eq('objekt_type', 'estate').eq('objekt_id', Number(estateId)).eq('subjekt_type', 'person'));
    return rows
      .map((r) => ({
        personId: String(r.subjekt_id),
        navn: model?.byId?.[String(r.subjekt_id)]?.name ?? `#${r.subjekt_id}`,
        rolle: r.rolle ?? '',
        periode: r.periode_raw ?? '',
      }))
      .sort((a, b) => a.periode.localeCompare(b.periode, 'da'));
  } catch {
    return [];
  }
}

export async function fetchArms(): Promise<ArmsItem[]> {
  try {
    const rows = await getAll<{ id: number; blasonering: string | null }>(() =>
      supabase.from('coat_of_arms').select('id,blasonering'));
    return rows.map((r) => ({ id: String(r.id), blasonering: r.blasonering ?? '' }));
  } catch {
    return [];
  }
}

// --- Person-detalje (bio + embeder + godser) til højre-panelet ---

export type PersonOffice = { label: string; period: string };
export type PersonEstate = { id: string; navn: string };
export type PersonDetailData = { bio: string; offices: PersonOffice[]; estates: PersonEstate[] };

type RawPersonRel = { objekt_type: string; objekt_id: number; rolle: string | null; periode_raw: string | null };

export async function fetchPersonDetail(id: string): Promise<PersonDetailData> {
  const empty: PersonDetailData = { bio: '', offices: [], estates: [] };
  try {
    const [narr, rels] = await Promise.all([
      supabase.from('narrative').select('tekst,privat').eq('subjekt_type', 'person').eq('subjekt_id', Number(id)).order('id', { ascending: true }).limit(1),
      getAll<RawPersonRel>(() => supabase.from('relation').select('objekt_type,objekt_id,rolle,periode_raw')
        .eq('subjekt_type', 'person').eq('subjekt_id', Number(id)).in('objekt_type', ['organisation', 'estate'])),
    ]);
    const bioRow = (narr.data ?? [])[0] as { tekst: string | null; privat: boolean | null } | undefined;
    const bio = bioRow && !bioRow.privat ? (bioRow.tekst ?? '') : '';
    const orgIds = rels.filter((r) => r.objekt_type === 'organisation').map((r) => r.objekt_id);
    const estIds = rels.filter((r) => r.objekt_type === 'estate').map((r) => r.objekt_id);
    const [orgs, ests] = await Promise.all([
      orgIds.length ? supabase.from('organisation').select('id,navn').in('id', orgIds) : Promise.resolve({ data: [] as { id: number; navn: string | null }[] }),
      estIds.length ? supabase.from('estate').select('id,navn').in('id', estIds) : Promise.resolve({ data: [] as { id: number; navn: string | null }[] }),
    ]);
    const orgNavn = new Map((orgs.data ?? []).map((o) => [String(o.id), o.navn ?? '']));
    const estNavn = new Map((ests.data ?? []).map((e) => [String(e.id), e.navn ?? '']));
    const offices = rels.filter((r) => r.objekt_type === 'organisation').map((r) => ({
      label: [r.rolle, orgNavn.get(String(r.objekt_id))].filter(Boolean).join(' · ') || `#${r.objekt_id}`,
      period: r.periode_raw ?? '',
    }));
    const estates = rels.filter((r) => r.objekt_type === 'estate').map((r) => ({
      id: String(r.objekt_id), navn: estNavn.get(String(r.objekt_id)) || `#${r.objekt_id}`,
    }));
    return { bio, offices, estates };
  } catch {
    return empty;
  }
}

// Indledende narrativer på slægts-niveau (subjekt_type 'slaegt'/'lineage') til "Om slægten".
export async function fetchAbout(): Promise<string[]> {
  try {
    const rows = await getAll<{ tekst: string | null; privat: boolean | null }>(() =>
      supabase.from('narrative').select('tekst,privat,subjekt_type').in('subjekt_type', ['slaegt', 'lineage']));
    return rows.filter((r) => !r.privat && r.tekst).map((r) => r.tekst as string);
  } catch {
    return [];
  }
}
