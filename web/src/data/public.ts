// Lean offentlige læse-queries til publikums-visningerne (Godser, Våben, Om, person-detalje).
// Fejlregel (review 36 K4): en hentning, hvis kalder viser en fejl med »Prøv igen« (besiddelser, ejerrække,
// persondetalje), KASTER — en databasefejl må ikke ligne tomme data. Kun ren ekstra pynt uden fejl-UI går gennem
// safe() nedenfor og giver en tom-tilstand (logget i konsollen).
import { supabase } from '../supabase';
import type { Model } from './types';
import type { EjerRelation } from './ejerraekke';
import { pickPreferredBio, buildBioSourceVersions, mapPublicBioSourceVersionsV2 as mapCorePublicBioSourceVersionsV2, selectDefaultPublicBioSourceVersionV2, buildBioVersions, getAll, buildProvenanceSources, citationRowsTilProveniens, buildPersonFacts, FAKTA_UDELADT, type BioSourceVersion, type BioSourceVersionV2, type NarrativeCand, type PersonFactView, type PublicPersonFactRow, type RaaCitationRow, type SourceRef, type Udgave, type UdgaveFaktaInput } from '@daa/core';
import { laesCitationer } from './citationLaes';
import { SLUKKET_ENIGHED } from './udgaver';
import { fetchPersonMedia, fetchObjectMedia, type MediaItem } from './media';

// Rå narrativ-række med source-join (PostgREST embedded resource).
type RawNarr = { id: number; subjekt_id: number | string; tekst: string | null; source_id: number | null; source: { slags: string | null; aar: number | null; udgave: string | null } | null };

class PublicNarrativeFetchError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PublicNarrativeFetchError';
  }
}

// Tolerant fallback — en dokumenteret undtagelse fra fejlreglen øverst (review 36 K4). Kun for hentninger, hvis
// kaldere IKKE har en fejl-tilstand, og hvor en tom visning er acceptabel: fetchArms (Våben-siden + feedets våbenkort),
// fetchAbout (»Om slægten«) og fetchEstateInfo (besiddelsens historik/beliggenhed/billeder; ejerrækken har sin egen
// fejl). Kalderne sætter også selv tom ved .catch. Får en af dem en fejl-UI, skal den ud af safe() og kaste.
async function safe<T>(fn: () => Promise<T>, fallback: T, label: string): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    console.warn(`[public] ${label} fejlede:`, e);
    return fallback;
  }
}

// Pakker et supabase-{data,error}-svar ud: kaster ved .error (en kastende hentning når kalderens fejl-UI; inde i
// safe() logges den og giver tom),
// returnerer ellers data. supabase-js kaster ikke selv, så uden dette bliver en RLS-/grant-fejl
// tavst til tom-tilstand (review 27 R1).
export function orThrow<T>(res: { data: T; error: unknown }, label: string): T {
  if (res.error) throw Object.assign(new Error(`${label}: ${(res.error as { message?: string })?.message ?? 'ukendt fejl'}`), { cause: res.error });
  return res.data;
}

// Den offentlige RPC er den eneste record-aware indgang. Udtræk felt-for-felt,
// så eventuelle fremtidige/private kolonner aldrig bliver en del af UI-kontrakten.
export function mapPublicBioSourceVersions(rows: unknown[]): BioSourceVersion[] {
  return buildBioSourceVersions(rows.flatMap((row) => {
    if (typeof row !== 'object' || row === null) return [];
    const value = row as Record<string, unknown>;
    const kind = value.provenance_kind;
    if ((kind !== 'source_record' && kind !== 'legacy_narrative')
      || (value.record_ref !== null && typeof value.record_ref !== 'string')
      || typeof value.source_label !== 'string' || typeof value.record_label !== 'string'
      || typeof value.narrative_text !== 'string' || typeof value.citation_label !== 'string') return [];
    return [{
      record_ref: value.record_ref,
      source_label: value.source_label,
      record_label: value.record_label,
      narrative_text: value.narrative_text,
      citation_label: value.citation_label,
      provenance_kind: kind,
    }];
  }));
}

// V2 validation and ordering live in core so web and mobile cannot diverge.
// It throws on malformed RPC rows; callers keep that as an explicit v2 fetch
// failure instead of guessing from the direct narrative table.
export function mapPublicBioSourceVersionsV2(rows: unknown[]) {
  return mapCorePublicBioSourceVersionsV2(rows);
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

// ejerIds: rå person-id'er med rollen »ejer« (før samme_som-fletning); ownerCount tælles om mod modellen i Folgesvend.
export type EstateItem = { id: string; navn: string; slags: string; ownerCount: number; ejerIds?: string[] };
export type ArmsItem = { id: string; blasonering: string; note: string; media: MediaItem[] };
export type EstateInfo = { narrativ: string; sted: string; media: MediaItem[] };

type RawEstate = { id: number; navn: string | null; slags: string | null };
type RawEstateRel = { subjekt_id: number; objekt_id: number; rolle: string | null; periode_raw: string | null };

// Kaster ved fejl (fase 7b): en fejlet hentning må ikke ligne »ingen besiddelser«. ownerCount er antal forskellige
// ejere (personer), ikke ejer-relationer — samme person med to perioder er én ejer.
export async function fetchEstates(): Promise<EstateItem[]> {
  const [estates, rels] = await Promise.all([
    getAll<RawEstate>(() => supabase.from('estate').select('id,navn,slags')),
    getAll<{ subjekt_id: number; objekt_id: number }>(() => supabase.from('relation').select('subjekt_id,objekt_id')
      .eq('objekt_type', 'estate').eq('subjekt_type', 'person').eq('rolle', 'ejer')),
  ]);
  const ejere: Record<string, Set<string>> = {};
  rels.forEach((r) => { (ejere[String(r.objekt_id)] ??= new Set()).add(String(r.subjekt_id)); });
  return estates
    .map((e) => ({ id: String(e.id), navn: e.navn ?? '(uden navn)', slags: e.slags ?? '', ownerCount: ejere[String(e.id)]?.size ?? 0, ejerIds: [...(ejere[String(e.id)] ?? [])] }))
    .sort((a, b) => b.ownerCount - a.ownerCount || a.navn.localeCompare(b.navn, 'da'));
}

// Ejer-relationerne for én besiddelse. En relation kan være registreret under et foldet alias-person-id → kanonisér
// via model.canonicalIdById. Navne, rækkefølge og udeladelse af ejere, læseren ikke kan se, sker i byggEjerraekke.
// Kaster ved fejl (fase 7b): en fejlet hentning må ikke ligne »ingen ejere«.
export async function fetchEstateOwners(estateId: string, model: Model | null): Promise<EjerRelation[]> {
  const canon = (id: string) => model?.canonicalIdById?.[id] ?? id;
  const rows = await getAll<RawEstateRel>(() =>
    supabase.from('relation').select('subjekt_id,objekt_id,rolle,periode_raw')
      .eq('objekt_type', 'estate').eq('objekt_id', Number(estateId)).eq('subjekt_type', 'person').eq('rolle', 'ejer'));
  return rows.map((r) => ({ personId: canon(String(r.subjekt_id)), periode: r.periode_raw ?? '' }));
}

export function fetchArms(): Promise<ArmsItem[]> {
  return safe(async () => {
    const rows = await getAll<{ id: number; blasonering: string | null; note: string | null }>(() =>
      supabase.from('coat_of_arms').select('id,blasonering,note'));
    // Objekt-billeder pr. våben (afbildet media→coat_of_arms) i ÉN batch (ikke N×3 rundture).
    const mediaByArm = await fetchObjectMedia('coat_of_arms', rows.map((r) => r.id));
    return rows.map((r) => ({ id: String(r.id), blasonering: r.blasonering ?? '', note: r.note ?? '', media: mediaByArm.get(String(r.id)) ?? [] }));
  }, [], 'fetchArms');
}

// Gods-detalje: historik-narrativ (offentlig) + beliggenhed (place via sted_id). Tolerant.
export function fetchEstateInfo(estateId: string): Promise<EstateInfo> {
  return safe(async () => {
    // Medie-fetchen afhænger kun af estateId → kør den samtidig med narrativ/sted-kæden (ikke bagefter).
    const mediaP = fetchObjectMedia('estate', [Number(estateId)]);
    const [narr, est] = await Promise.all([
      supabase.from('narrative').select('tekst').eq('subjekt_type', 'estate').eq('subjekt_id', Number(estateId))
        .eq('privat', false).order('id', { ascending: true }).limit(1),
      supabase.from('estate').select('sted_id').eq('id', Number(estateId)).maybeSingle(),
    ]);
    const narrativ = ((orThrow(narr, 'fetchEstateInfo/narrative') ?? [])[0] as { tekst: string | null } | undefined)?.tekst ?? '';
    let sted = '';
    const stedId = (orThrow(est, 'fetchEstateInfo/estate') as { sted_id: number | null } | null)?.sted_id;
    if (stedId) {
      const plRes = await supabase.from('place').select('navn').eq('id', stedId).maybeSingle();
      const pl = orThrow(plRes, 'fetchEstateInfo/place');
      sted = (pl as { navn: string | null } | null)?.navn ?? '';
    }
    const media = (await mediaP).get(estateId) ?? [];
    return { narrativ, sted, media };
  }, { narrativ: '', sted: '', media: [] }, 'fetchEstateInfo');
}

// --- Person-detalje (bio + embeder + godser) til højre-panelet ---

// Slå organisation/estate-navne op i ét hug (delt af person-detalje + relations-læsning).
export async function resolveOrgEstateNames(orgIds: number[], estIds: number[]): Promise<{ org: Map<string, string>; estate: Map<string, string> }> {
  const [orgs, ests] = await Promise.all([
    orgIds.length ? supabase.from('organisation').select('id,navn').in('id', orgIds) : Promise.resolve({ data: [] as { id: number; navn: string | null }[], error: null }),
    estIds.length ? supabase.from('estate').select('id,navn').in('id', estIds) : Promise.resolve({ data: [] as { id: number; navn: string | null }[], error: null }),
  ]);
  return {
    org: new Map((orThrow(orgs, 'resolveOrgEstateNames/organisation') ?? []).map((o) => [String(o.id), o.navn ?? ''])),
    estate: new Map((orThrow(ests, 'resolveOrgEstateNames/estate') ?? []).map((e) => [String(e.id), e.navn ?? ''])),
  };
}

export type PersonOffice = { label: string; period: string };
export type PersonEstate = { id: string; navn: string; personId: string };
// bioVersions: alle offentlige DAA-udgave-versioner af biografien, nyeste først (§7.18
// versionsvælger). bio er altid = bioVersions[0]?.tekst (bagudkompatibel — mobile og øvrige
// kaldere der kun læser .bio er upåvirkede).
// sources: kilde udledt af EVIDENSLAGET (citation→source). Hentes kun når personen ikke har et
// bog-nummer (person_external_id) — se hentKilder nedenfor.
// facts/factsError (B11, spec 2026-10-29 §4.3-4.4): personens fakta med kilde fra public_person_facts; en fejl dér
// sætter factsError, så sektionen siger det i stedet for at stå tom, mens resten af detaljen vises.
// facts: forældet i web — brug faktaInput/byggUdgaveFakta (bevares for planens kompatibilitet).
export type PersonDetailData = { bio: string; bioVersions: BioSourceVersion[]; offices: PersonOffice[]; estates: PersonEstate[]; media: MediaItem[]; sources: SourceRef[]; facts: PersonFactView[]; factsError: boolean; faktaInput: UdgaveFaktaInput | null };

type RawPersonRel = { subjekt_id: number | string; objekt_type: string; objekt_id: number; rolle: string | null; periode_raw: string | null };

// Proveniens for personer UDEN bog-nummer (de 627 ægtefæller): fact → assertion → citation →
// source. Tre flade opslag, fordi assertion.target_id er polymorf og derfor uden FK at neste på.
async function fetchProveniens(numIds: number[]): Promise<SourceRef[]> {
  if (!numIds.length) return [];
  // Fejl i fact/assertion kaster (review 36 K4): personsiden viser fejlen med »Prøv igen« frem for »ingen kilde«.
  // Citationerne læses tolerant af laesCitationer (dokumenteret overgang til 6e-2's DDL).
  const facts = orThrow(await supabase.from('fact')
    .select('id,subjekt_id').eq('subjekt_type', 'person').in('subjekt_id', numIds), 'fetchProveniens/fact');
  const factRows = (facts ?? []) as { id: number; subjekt_id: number }[];
  if (!factRows.length) return [];
  const asserts = orThrow(await supabase.from('assertion')
    .select('id,target_id').eq('target_type', 'fact').in('target_id', factRows.map((f) => f.id)), 'fetchProveniens/assertion');
  const assertRows = (asserts ?? []) as { id: number; target_id: number }[];
  if (!assertRows.length) return [];
  const assertIds = assertRows.map((a) => a.id);
  const cits = await laesCitationer((medSideTrykt) => supabase.from('citation')
    .select(medSideTrykt ? 'assertion_id,side,side_trykt,source:source_id(titel,udgave)' : 'assertion_id,side,source:source_id(titel,udgave)')
    .in('assertion_id', assertIds));
  const personAfFact = new Map(factRows.map((f) => [f.id, String(f.subjekt_id)]));
  const personAfAssert = new Map(assertRows.map((a) => [a.id, personAfFact.get(a.target_id) ?? '']));
  const rows = citationRowsTilProveniens((cits ?? []) as unknown as RaaCitationRow[], personAfAssert);
  // Alle medlems-id'er hører til den samme foldede person her, så de samles under én nøgle.
  const perPerson = buildProvenanceSources(rows, Object.fromEntries(numIds.map((n) => [String(n), String(numIds[0])])));
  return perPerson[String(numIds[0])] ?? [];
}

// Embede-etiket: »rolle · organisation«, men organisationen udelades når den (uden forskel på store/små
// bogstaver) blot gentager rollen.
function embedeLabel(rolle: string | null, org: string | undefined): string {
  const r = rolle ?? '';
  const o = org && r && org.toLocaleLowerCase('da') === r.toLocaleLowerCase('da') ? '' : org;
  return [r, o].filter(Boolean).join(' · ');
}

// Redaktørens egen kildetekst (citation uden source_id) for valgte påstande uden kilde og uden bogpost.
// Enhver fejl giver {} — fakta vises stadig; det er ikke en faktafejl. Typer, fakta-visningen udelader
// (forældrefamilie, forældre_ukendt), udløser intet opslag: personsiden må ikke betale for dem.
async function fetchFritekstKilde(rows: PublicPersonFactRow[]): Promise<Record<string, string[]>> {
  const ids = [...new Set(rows
    .filter((r) => r.chosen === true && r.source_id == null && !r.record_ref && !FAKTA_UDELADT.includes(r.faktatype))
    .map((r) => r.assertion_id))];
  if (!ids.length) return {};
  try {
    const res = await supabase.from('citation').select('assertion_id,citat_tekst').is('source_id', null).in('assertion_id', ids as number[]);
    if (res.error) return {};
    const ud: Record<string, string[]> = {};
    for (const c of (res.data ?? []) as unknown as { assertion_id: number | string; citat_tekst: string | null }[]) {
      if (!c.citat_tekst || !c.citat_tekst.trim()) continue;
      (ud[String(c.assertion_id)] ??= []).push(c.citat_tekst);
    }
    return ud;
  } catch {
    return {};
  }
}

// Redaktøren ser levende (decisions 2026-11-13, trin 2). Udgivelsesreglen tillader aldrig udgivelse af en levende,
// privat eller staged persons biografi (publication_allowed er bagt ind i den hash-bundne tilstand), så den findes kun
// som kladde. For redaktøren hentes kladden med kildehenvisning fra den eksisterende redaktør-RPC for de medlemmer,
// gæster ikke kan se, og mærkes kunRedaktion. En fejl logges og koster kun det berørte medlems kladder; resten af
// personsiden står. redaktionRead importerer public.ts, derfor dynamisk import (bryder cirklen og holder koden ude af
// læserens vej).
const KLADDE_STATUS = new Set(['draft', 'published', 'stale_published']);
async function fetchRedaktionKladder(numIds: number[]): Promise<BioSourceVersionV2[]> {
  try {
    const res = await supabase.from('person').select('id,levende,privat,staged').in('id', numIds);
    if (res.error) {
      console.warn('[fetchPersonDetail] redaktørens kladder: personopslag fejlede — ingen kladder:', res.error);
      return [];
    }
    const skjulte = ((res.data ?? []) as { id: number | string; levende: boolean | null; privat: boolean | null; staged: boolean | null }[])
      // Samme regel som person_offentlig: kun levende=false, ikke privat og ikke staged er offentlig (NULL = skjult).
      .filter((p) => p.levende !== false || p.privat === true || p.staged === true)
      .map((p) => Number(p.id))
      .filter((n) => Number.isSafeInteger(n) && n > 0)
      .sort((a, b) => a - b);
    if (!skjulte.length) return [];
    const { mapNarrativeRecordRows } = await import('./redaktionRead');
    const svar = await Promise.all(skjulte.map(async (pid) => {
      try {
        const r = await supabase.rpc('red_person_narrative_records', { p_person_id: pid });
        if (r.error || !Array.isArray(r.data)) throw new Error(String((r.error as { message?: string } | null)?.message ?? 'svar er ikke en liste'));
        return mapNarrativeRecordRows(r.data as Parameters<typeof mapNarrativeRecordRows>[0]).records
          .filter((x) => KLADDE_STATUS.has(x.status) && x.text.trim() !== '')
          .map((x): BioSourceVersionV2 => ({
            personId: pid, sourceId: x.sourceId, sourceYear: x.sourceYear, recordOrder: null,
            sourceRecordRef: x.sourceRecordRef, recordRef: x.sourceRecordRef,
            sourceLabel: x.sourceLabel, recordLabel: x.recordLabel, citationLabel: x.citationLabel,
            narrativeText: x.text.trim(), provenanceKind: 'source_record', kunRedaktion: true,
          }));
      } catch (e) {
        console.warn(`[fetchPersonDetail] redaktørens kladder for person ${pid} fejlede — ingen kladder for den:`, e);
        return [] as BioSourceVersionV2[];
      }
    }));
    return svar.flat();
  } catch (e) {
    console.warn('[fetchPersonDetail] redaktørens kladder fejlede — ingen kladder:', e);
    return [];
  }
}

// memberIds: for en samme_som-foldet person, alle medlems-id'er i gruppen — narrativ + relationer
// unioneres over dem (spec §8). Uden memberIds (ikke-foldet) = kun personens eget id.
// hentKilder: kun sandt når personen mangler bog-nummer, så de ~1129 hovedposter ikke betaler for
// tre ekstra opslag de alligevel ikke bruger.
// redaktoer: kalderen er logget ind med rollen redaktion (kladder for ikke-offentlige medlemmer, se ovenfor).
// Kaster ved fejl (review 36 K4): begge kaldere (personpanelet/-siden og præsenslisten) viser fejlen og kan prøve igen,
// så et fejlet relations-, navne- eller kildeopslag må ikke blive til en tom person. Bevidst tolerante delopslag:
// fakta (factsError), redaktørens fritekstkilder og kladder, billeder (media.ts) og citationer (laesCitationer).
export function fetchPersonDetail(id: string, memberIds?: string[], hentKilder = false, udgaveKontekst?: { udgaver: Udgave[]; udgaveForPersonRaekke: Record<string, string> }, redaktoer = false): Promise<PersonDetailData> {
  const ids = memberIds && memberIds.length ? memberIds : [id];
  const numIds = ids.map(Number).filter((n) => !Number.isNaN(n));
  return (async () => {
    const rpcClient = supabase as unknown as { rpc?: (name: string, args: unknown) => Promise<{ data: unknown; error: unknown }> };
    const hasRpc = typeof rpcClient.rpc === 'function';
    if (!hasRpc) {
      throw new PublicNarrativeFetchError('NARRATIVE_RECORD_CONTRACT_VERSION_UNAVAILABLE');
    }
    let versionResult: { data: unknown; error: unknown };
    try {
      versionResult = await rpcClient.rpc!('narrative_record_contract_version', {});
    } catch {
      throw new PublicNarrativeFetchError('NARRATIVE_RECORD_CONTRACT_VERSION_UNAVAILABLE');
    }
    if (versionResult.error || typeof versionResult.data !== 'number' || !Number.isInteger(versionResult.data)) {
      throw new PublicNarrativeFetchError('NARRATIVE_RECORD_CONTRACT_VERSION_UNAVAILABLE');
    }
    const contractVersion = versionResult.data;
    const usesV2 = contractVersion >= 2;
    const [narr, rels, media, rpcVersions, factRows, kladder] = await Promise.all([
      // V1 keeps its existing fallback query.  At contract v2 this query is
      // never issued: event text is available only through the v2 RPC.
      usesV2
        ? Promise.resolve({ data: [] as RawNarr[], error: null })
        : supabase.from('narrative').select('id,subjekt_id,tekst,source_id,source:source_id(slags,aar,udgave)')
          .eq('subjekt_type', 'person').in('subjekt_id', numIds)
          .eq('privat', false).order('id', { ascending: true }),
      getAll<RawPersonRel>(() => supabase.from('relation').select('subjekt_id,objekt_type,objekt_id,rolle,periode_raw')
        .eq('subjekt_type', 'person').in('subjekt_id', numIds).in('objekt_type', ['organisation', 'estate'])),
      // Portræt/materiale: union over foldede medlems-id'er (afbildet person→media). RLS-gatet.
      fetchPersonMedia(numIds),
      // The contract version, not an RPC error, selects the reader.  A v2
      // failure rejects the complete biography fetch and never reaches v1.
      Promise.resolve()
        .then(() => rpcClient.rpc!(usesV2 ? 'public_person_bio_source_versions_v2' : 'public_person_bio_source_versions', { p_person_ids: numIds }))
        .then((res) => {
          if (res.error || !Array.isArray(res.data)) {
            if (usesV2) throw new PublicNarrativeFetchError('PUBLIC_BIO_SOURCE_V2_UNAVAILABLE');
            return null;
          }
          if (!usesV2) return mapPublicBioSourceVersions(res.data);
          try {
            return mapPublicBioSourceVersionsV2(res.data);
          } catch (e) {
            throw new PublicNarrativeFetchError(String((e as Error)?.message ?? 'PUBLIC_BIO_SOURCE_V2_INVALID'));
          }
        }, () => {
          if (usesV2) throw new PublicNarrativeFetchError('PUBLIC_BIO_SOURCE_V2_UNAVAILABLE');
          // v1: en afvist RPC behandles som et fejlsvar ovenfor — fald tilbage til narrative-tabellen. (Før review 36
          // K4 slugte safe() kastet og gav en helt tom person.)
          return null;
        }),
      // B11: fakta med kilde for alle medlems-id'er; null = fejl (sektionen siger det, resten står).
      Promise.resolve()
        .then(() => rpcClient.rpc!('public_person_facts', { p_person_ids: numIds }))
        .then((res) => (!res || res.error || !Array.isArray(res.data) ? null : (res.data as PublicPersonFactRow[])))
        // .catch, ikke then(_, fejl): også et kast i selve svarbehandlingen må kun ramme fakta-sektionen.
        .catch(() => null),
      usesV2 && redaktoer ? fetchRedaktionKladder(numIds) : Promise.resolve([] as BioSourceVersionV2[]),
    ]);
    // Udgave-versioner (§7.18): ÉN version pr. DAA-udgave, nyeste først. Kandidater ordnet
    // kanonisk (id) FØRST, så en samme_som-foldet person med narrativ i samme udgave fra
    // flere medlemmer sammenføjer den fulde founder-bio før en kort kryds-reference-stub.
    const candsByMember = new Map<string, NarrativeCand[]>();
    for (const n of (orThrow(narr as { data: unknown; error: unknown }, 'fetchPersonDetail/narrative') ?? []) as RawNarr[]) {
      const k = String(n.subjekt_id);
      const arr = candsByMember.get(k) ?? [];
      arr.push({ narrativeId: n.id, tekst: n.tekst, sourceId: n.source_id, slags: n.source?.slags ?? null, aar: n.source?.aar ?? null, udgave: n.source?.udgave ?? null });
      candsByMember.set(k, arr);
    }
    const orderedIds = [id, ...ids.filter((m) => m !== id)];
    const allCands = orderedIds.flatMap((mid) => candsByMember.get(mid) ?? []);
    const fallbackVersions = buildBioVersions(allCands).map((version) => ({
      recordRef: null,
      sourceLabel: version.udgave ?? (version.aar != null ? String(version.aar) : 'DAA-udgave'),
      recordLabel: 'Overgangsdata',
      narrativeText: version.tekst,
      citationLabel: '',
      provenanceKind: 'legacy_narrative' as const,
    }));
    // Kladderne (kun redaktør, kun ikke-offentlige medlemmer) står efter de offentlige versioner; detail.bio er den
    // offentlige tekst, når den findes. Personsidens udgavevælger kan stadig åbne på en kladde (nyeste udgave), som så
    // bærer mærkatet.
    const v2Versions = [...((rpcVersions ?? []) as BioSourceVersionV2[]), ...kladder];
    const bioVersions = usesV2 ? v2Versions : (rpcVersions && rpcVersions.length ? rpcVersions : fallbackVersions);
    const bio = usesV2
      ? (selectDefaultPublicBioSourceVersionV2((rpcVersions ?? []) as BioSourceVersionV2[])
        ?? selectDefaultPublicBioSourceVersionV2(kladder))?.narrativeText ?? ''
      : bioVersions[0]?.narrativeText ?? '';
    const orgIds = rels.filter((r) => r.objekt_type === 'organisation').map((r) => r.objekt_id);
    const estIds = rels.filter((r) => r.objekt_type === 'estate').map((r) => r.objekt_id);
    // Navne og redaktørens kildetekster i samme bølge (ingen ekstra seriel rundtur for personsiden).
    const [{ org: orgNavn, estate: estNavn }, fritekstKilde] = await Promise.all([
      resolveOrgEstateNames(orgIds, estIds),
      factRows ? fetchFritekstKilde(factRows) : Promise.resolve({} as Record<string, string[]>),
    ]);
    // Dedup ved union over foldede medlemmer: samme embede/gods fra to medlems-poster → én.
    const offices = dedupBy(
      rels.filter((r) => r.objekt_type === 'organisation').map((r) => ({
        label: embedeLabel(r.rolle, orgNavn.get(String(r.objekt_id))) || `#${r.objekt_id}`,
        period: r.periode_raw ?? '',
      })),
      (o) => `${o.label}|${o.period}`,
    );
    const estates = dedupBy(
      rels.filter((r) => r.objekt_type === 'estate').map((r) => ({
        id: String(r.objekt_id), navn: estNavn.get(String(r.objekt_id)) || `#${r.objekt_id}`, personId: String(r.subjekt_id),
      })),
      (e) => `${e.personId}|${e.id}`,
    );
    const sources = hentKilder ? await fetchProveniens(numIds) : [];
    const facts = factRows ? buildPersonFacts(factRows) : []; // forældet i web — brug faktaInput/byggUdgaveFakta
    const faktaInput: UdgaveFaktaInput | null = factRows
      ? {
        rows: factRows,
        udgaver: udgaveKontekst?.udgaver ?? [],
        udgaveForPersonRaekke: udgaveKontekst?.udgaveForPersonRaekke ?? {},
        fritekstKilde,
        slukketEnighed: SLUKKET_ENIGHED,
      }
      : null;
    return { bio, bioVersions, offices, estates, media, sources, facts, factsError: factRows === null, faktaInput };
  })();
}

// Indledende narrativer på slægts-niveau (subjekt_type 'slaegt'/'lineage') til "Om slægten".
// Udvidet (billeder-i-narrativer 2026-07-05, Slice C4): hver linje/"Generelt" kan nu have FLERE
// udgaver (edition-faner, Slice C3) — pickPreferredBio (samme selector som person-bio) vælger én
// pr. subjekt (nyeste DAA-udgave). lineageNavn bærer overskriften pr. linje-afsnit; "Generelt" har
// ingen (null) og vises altid FØRST, linjer derefter i lineage.kode-orden.
// lineageId (lineage.id) skelner linjeafsnit fra slægtens eget afsnit (null) og er afsnittets
// nøgle; lineageKode er bogens kode for linjen i den udgave, rækken stammer fra. kilde er udgavens
// etiket efter samme regel som udgavevælgeren (data/udgaver.ts: udgave ?? titel), så indledningen
// og personsiden nævner udgaven ens.
export type AboutSection = { lineageId: string | null; lineageNavn: string | null; lineageKode: string | null; tekst: string; kilde: string | null; aar: number | null };

type RawAboutSource = { slags: string | null; titel?: string | null; aar: number | null; udgave: string | null };
export type RawAboutRow = { id: number; subjekt_type: string; subjekt_id: number; source_id: number | null; tekst: string | null; source: RawAboutSource | null };
export type RawAboutLineage = { id: number; navn: string | null; kode: string };

// Ren: narrativ-rækker + linjer → afsnit. "Generelt" (slaegt) først, linjer i kode-orden.
export function byggAboutSections(rows: RawAboutRow[], lineageRows: RawAboutLineage[]): AboutSection[] {
  const candsByKey = new Map<string, NarrativeCand[]>();
  const sourceById = new Map<number, RawAboutSource>();
  for (const r of rows) {
    const key = `${r.subjekt_type}:${r.subjekt_id}`;
    const cand: NarrativeCand = { narrativeId: r.id, tekst: r.tekst, sourceId: r.source_id, slags: r.source?.slags ?? null, aar: r.source?.aar ?? null, udgave: r.source?.udgave ?? null };
    if (r.source_id != null && r.source) sourceById.set(r.source_id, r.source);
    const list = candsByKey.get(key);
    if (list) list.push(cand); else candsByKey.set(key, [cand]);
  }
  const kildeAf = (c: NarrativeCand) => {
    const s = c.sourceId != null ? sourceById.get(c.sourceId) : undefined;
    return { kilde: s ? (s.udgave ?? s.titel ?? null) : null, aar: s?.aar ?? null };
  };

  const sections: AboutSection[] = [];
  const slaegtCands = [...candsByKey.entries()].find(([key]) => key.startsWith('slaegt:'))?.[1];
  const slaegtBedst = slaegtCands ? pickPreferredBio(slaegtCands) : null;
  if (slaegtBedst?.tekst) sections.push({ lineageId: null, lineageNavn: null, lineageKode: null, tekst: slaegtBedst.tekst, ...kildeAf(slaegtBedst) });
  for (const l of lineageRows) {
    const cands = candsByKey.get(`lineage:${l.id}`);
    const best = cands ? pickPreferredBio(cands) : null;
    if (best?.tekst) sections.push({ lineageId: String(l.id), lineageNavn: l.navn ?? `Linje ${l.kode}`, lineageKode: l.kode, tekst: best.tekst, ...kildeAf(best) });
  }
  return sections;
}

export function fetchAbout(): Promise<AboutSection[]> {
  return safe(async () => {
    // Håndfuld rækker (6 subjekter × få udgaver) — ingen getAll-paginering nødvendig. Rå cast
    // (samme mønster som RawNarr ovenfor): Supabases genererede typer for et embedded
    // source_id(...)-join matcher ikke automatisk to-en-kardinalitet.
    const [narr, lin] = await Promise.all([
      // privat filtreres i query (matcher fetchPersonDetail/fetchEstateInfo); RLS gater også
      // privat for anon+auth — empirisk verificeret mod prod 2026-07-12.
      supabase.from('narrative').select('id,subjekt_type,subjekt_id,source_id,tekst,source:source_id(slags,titel,aar,udgave)').in('subjekt_type', ['slaegt', 'lineage']).eq('privat', false),
      supabase.from('lineage').select('id,navn,kode').order('kode', { ascending: true }),
    ]);
    const rows = (orThrow(narr, 'fetchAbout/narrative') ?? []) as unknown as RawAboutRow[];
    const lineageRows = (orThrow(lin, 'fetchAbout/lineage') ?? []) as RawAboutLineage[];
    return byggAboutSections(rows, lineageRows);
  }, [], 'fetchAbout');
}
