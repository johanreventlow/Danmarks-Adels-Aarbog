// PORTERET fra mobile/src/data/redaktionWrite.ts — hold i sync (web udvider med buildSuggestCall
// + planCall rolle-routing). Delt-pakke-ekstraktion er en follow-up.
// Oversætter en UI-redigering ("change") til ét RPC-kald mod skrive-laget (Task 3–6).
// Ren build-funktion (buildRpcCall) er netværksfri og unit-testes; submitChange udfører.
import { supabase } from '../supabase';
import { performUpload } from './mediaUpload';
import type { ResizedVariant } from './mediaUpload';

// felt → fact.faktatype. koen er BEVIDST udeladt: arbejdsværdi på person, ikke et fact.
// daab/begravelse/floruit/naturalisering er del af rygraden og lå allerede i DB (loaderen
// skriver dem fra extraction — se load_daa.R:298-299), men var utilgængelige i redaktions-UI
// før denne udvidelse (dato-analyse fund #5, docs/plan-1939-produktionsklar.md Wave 3).
export const FELT_FAKTATYPE: Record<string, string> = {
  navn: 'navn', foedt: 'fødsel', doed: 'død', titel: 'titel',
  daab: 'dåb', begravelse: 'begravelse', floruit: 'floruit', naturalisering: 'naturalisering',
};
const DATE_FELT = new Set(['foedt', 'doed', 'daab', 'begravelse', 'floruit', 'naturalisering']);

export type Change = {
  art: 'fakta' | 'narrativ' | 'relation' | 'gods' | 'hverv'
     | 'redigerOplysning' | 'sletOplysning' | 'setKonklusion' | 'setPrivat' | 'sletPerson'
     | 'tilfoejOplysning' | 'opretFakta' | 'sletRelation' | 'tilfoejRelation'
     | 'opretUnion' | 'tilfoejBarn' | 'setFamilieKonfidens' | 'sletFamilieLink'
     | 'setFamilieOrdinal' | 'flytBarn'
     | 'sammeSom' | 'fjernSammeSom' // redaktionel identitets-sammenkædning (samme_som)
     | 'ikkeSammeSom' | 'fjernIkkeSammeSom' // persisteret identitets-afvisning (tværudgave §4)
     | 'publicerPersoner' // K2 selektiv publicering — rydder staged for udvalgte person-id'er (§7.20)
     | 'foraeldrePaastand' | 'vaelgForaeldre' // konkurrerende forældrefamilie-påstande (Problem 2)
     | 'markerForaeldreUkendt' // "forældre ukendt"-markering (docs/reviews/25); fjern = 'tilbagetraekFakta'
     | 'tilbagetraekFakta' // tilbagetræk et fakta-slots konklusion (fjern markering korrekt — review 26 HIGH 2)
     | 'opretKilde' // opret ny source (DAA-udgave) — routes gennem submitChange (dry-run/staging)
     | 'haendelseStatus'
     | 'opretStory' | 'redigerStory' | 'setStoryStatus' | 'sletStory' | 'setStoryKilder'
     | 'setFeedPin' | 'fjernFeedPin'
     | 'uploadMedia' // mediehåndtering Slice 0g — redaktør-upload (portræt/objekt-foto)
     | 'opdaterMedia' | 'genopretMedia' | 'mediaRettigheder' // fase 1 filside
     | 'tilknytMedia' // fase 2: genbrug eksisterende medie via red_relation
     | 'fjernMedia' // Slice 0h — blødt fjern (upload_status='fjernet'); unlink går via sletRelation
     | 'forslag'; // generisk entitets-feltredigering uden direkte RPC → red_suggest
  subjektType: string;
  subjektId: string;
  assertionId?: string;
  factId?: string;
  relationId?: string;
  mediaId?: string;
  haendelseId?: number;
  status?: 'kandidat' | 'interessant' | 'skjult';
  storyId?: number;
  storyStatus?: 'kladde' | 'klar' | 'publiceret' | 'arkiveret';
  kortNoegle?: string;
  handling?: 'pin' | 'skjul';
  kilder?: { sourceId: number; side?: string }[];
  familyId?: string;
  tilFamilyId?: string;
  personId?: string;
  rolle?: string;
  konfidens?: string | null;
  ordinal?: number | null;
  felt?: string;
  vaerdi?: string;
  kildeFritekst?: string;
  payload?: Record<string, unknown>;
};

export type RpcCall = { fn: string; args: Record<string, unknown> };

export type ResumeMediaUploadStep =
  | { kind: 'upload'; file: Blob; storagePath: string }
  | { kind: 'rpc'; fn: 'red_bekraeft_media_upload' | 'red_registrer_media_variant'; args: Record<string, unknown> };

function parsePostgresBigintId(value: unknown): number | string | null {
  const raw = typeof value === 'number' ? String(value) : typeof value === 'string' ? value.trim() : '';
  if (!/^[1-9][0-9]*$/.test(raw) || raw.length > 19 || (raw.length === 19 && raw > '9223372036854775807')) return null;
  const id = Number(raw);
  return Number.isSafeInteger(id) ? id : raw;
}

// Ren genoptagelsesplan: samme write-once Storage-stier kan uploades idempotent, mens alle RPC'er
// målrettes den allerede eksisterende kladde. Bekræftelsen gentager bevidst ikke sha256 — guarden
// har allerede kørt, før rækken blev oprettet.
export function buildResumeMediaUploadPlan(
  mediaId: string,
  large: ResizedVariant,
  variants: ResizedVariant[],
): ResumeMediaUploadStep[] {
  const parsedMediaId = parsePostgresBigintId(mediaId);
  if (parsedMediaId == null) throw new Error('Ugyldigt media-id ved genoptagelse.');
  return [
    { kind: 'upload', file: large.file, storagePath: large.storagePath },
    ...variants.flatMap((variant): ResumeMediaUploadStep[] => [
      { kind: 'upload', file: variant.file, storagePath: variant.storagePath },
      { kind: 'rpc', fn: 'red_registrer_media_variant', args: {
        p_media_id: parsedMediaId, p_tier: variant.tier, p_storage_path: variant.storagePath,
        p_mime: variant.mimeType, p_byte_size: variant.byteSize,
        p_bredde: variant.bredde, p_hoejde: variant.hoejde,
      } },
    ]),
    { kind: 'rpc', fn: 'red_bekraeft_media_upload', args: { p_media_id: parsedMediaId } },
  ];
}

export async function resumeMediaUpload(
  mediaId: string,
  large: ResizedVariant,
  variants: ResizedVariant[],
): Promise<void> {
  for (const step of buildResumeMediaUploadPlan(mediaId, large, variants)) {
    if (step.kind === 'upload') {
      await performUpload(step.file, step.storagePath);
      continue;
    }
    const { error } = await supabase.rpc(step.fn, step.args);
    if (error) throw new Error(error.message);
  }
}

function famLinkBase(c: Change): { p_family_id: number; p_person_id: number; p_rolle: string } | null {
  if (c.familyId == null || c.personId == null || !c.rolle) return null;
  return { p_family_id: Number(c.familyId), p_person_id: Number(c.personId), p_rolle: c.rolle };
}

function storyPayloadArgs(p: Record<string, unknown>): Record<string, unknown> {
  return {
    p_titel: (p.titel as string | null | undefined) ?? null,
    p_haendelse_id: p.haendelseId != null ? Number(p.haendelseId) : null,
    p_fact_id: p.factId != null ? Number(p.factId) : null,
    p_relation_id: p.relationId != null ? Number(p.relationId) : null,
    p_historical_event_id: p.historicalEventId != null ? Number(p.historicalEventId) : null,
    p_date_min: (p.dateMin as string | null | undefined) ?? null,
    p_date_max: (p.dateMax as string | null | undefined) ?? null,
    p_date_qualifier: (p.dateQualifier as string | null | undefined) ?? null,
    p_date_raw: (p.dateRaw as string | null | undefined) ?? null,
    p_privat: Boolean(p.privat),
  };
}

export function buildRpcCall(c: Change): RpcCall | null {
  const sid = Number(c.subjektId);
  const aid = c.assertionId != null ? Number(c.assertionId) : null;
  if (c.art === 'haendelseStatus') {
    if (c.haendelseId == null || !Number.isFinite(c.haendelseId) || !c.status || !['kandidat','interessant','skjult'].includes(c.status)) return null;
    return { fn: 'red_set_haendelse_status', args: { p_haendelse_id: c.haendelseId, p_status: c.status } };
  }
  if (c.art === 'opretStory') {
    const p = c.payload || {};
    const tekst = typeof p.tekst === 'string' ? p.tekst.trim() : '';
    if (!tekst) return null;
    return { fn: 'red_opret_story', args: {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid, p_tekst: tekst, ...storyPayloadArgs(p),
    } };
  }
  if (c.art === 'redigerStory') {
    const p = c.payload || {};
    const tekst = typeof p.tekst === 'string' ? p.tekst.trim() : '';
    if (c.storyId == null || !Number.isFinite(c.storyId) || !tekst) return null;
    return { fn: 'red_rediger_story', args: {
      p_story_id: c.storyId, p_tekst: tekst, ...storyPayloadArgs(p),
    } };
  }
  if (c.art === 'setStoryStatus') {
    if (c.storyId == null || !Number.isFinite(c.storyId) || !c.storyStatus
        || !['kladde', 'klar', 'publiceret', 'arkiveret'].includes(c.storyStatus)) return null;
    return { fn: 'red_set_story_status', args: { p_story_id: c.storyId, p_status: c.storyStatus } };
  }
  if (c.art === 'sletStory') {
    if (c.storyId == null || !Number.isFinite(c.storyId)) return null;
    return { fn: 'red_slet_story', args: { p_story_id: c.storyId } };
  }
  if (c.art === 'setStoryKilder') {
    if (c.storyId == null || !Number.isFinite(c.storyId) || !Array.isArray(c.kilder)) return null;
    if (c.kilder.some((k) => k.sourceId == null || !Number.isFinite(Number(k.sourceId)))) return null;
    return { fn: 'red_set_story_kilder', args: {
      p_story_id: c.storyId,
      p_kilder: c.kilder.map((k) => ({ source_id: Number(k.sourceId), side: k.side ?? null })),
    } };
  }
  if (c.art === 'setFeedPin') {
    if (!c.kortNoegle || c.kortNoegle.trim() === '' || !c.handling
        || !['pin', 'skjul'].includes(c.handling)) return null;
    return { fn: 'red_set_feed_pin', args: { p_kort_noegle: c.kortNoegle, p_handling: c.handling } };
  }
  if (c.art === 'fjernFeedPin') {
    if (!c.kortNoegle || c.kortNoegle.trim() === '') return null;
    return { fn: 'red_fjern_feed_pin', args: { p_kort_noegle: c.kortNoegle } };
  }
  if (c.art === 'setKonklusion') {
    if (aid == null) return null;
    return { fn: 'red_set_konklusion', args: { p_assertion_id: aid } };
  }
  if (c.art === 'redigerOplysning') {
    if (aid == null) return null;
    const args: Record<string, unknown> = { p_assertion_id: aid, p_vaerdi: c.vaerdi };
    if (c.felt && DATE_FELT.has(c.felt)) args.p_date_raw = c.vaerdi;
    if (c.kildeFritekst != null) args.p_kilde_fritekst = c.kildeFritekst;
    return { fn: 'red_edit_oplysning', args };
  }
  if (c.art === 'sletOplysning') {
    if (aid == null) return null;
    return { fn: 'red_slet_oplysning', args: { p_assertion_id: aid } };
  }
  if (c.art === 'setPrivat') {
    return { fn: 'red_set_privat', args: { p_person_id: sid, p_privat: Boolean(c.payload?.privat) } };
  }
  if (c.art === 'sletPerson') {
    return { fn: 'red_slet_person', args: { p_person_id: sid } };
  }
  // Operation A: tilføj oplysning til EKSISTERENDE fact (fact-målrettet, fact-kardinalitet).
  if (c.art === 'tilfoejOplysning') {
    const fid = c.factId != null ? Number(c.factId) : null;
    if (fid == null) return null;
    const args: Record<string, unknown> = { p_fact_id: fid, p_vaerdi: c.vaerdi };
    if (c.felt && DATE_FELT.has(c.felt)) args.p_date_raw = c.vaerdi;
    if (c.kildeFritekst != null) args.p_kilde_fritekst = c.kildeFritekst;
    return { fn: 'red_tilfoej_oplysning', args };
  }
  // Operation B: opret NYT distinkt fact (fx ny titel).
  if (c.art === 'opretFakta' && c.felt && FELT_FAKTATYPE[c.felt]) {
    const args: Record<string, unknown> = {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid,
      p_faktatype: FELT_FAKTATYPE[c.felt], p_vaerdi: c.vaerdi,
    };
    if (DATE_FELT.has(c.felt)) args.p_date_raw = c.vaerdi;
    if (c.kildeFritekst != null) args.p_kilde_fritekst = c.kildeFritekst;
    return { fn: 'red_opret_fakta', args };
  }
  if (c.art === 'fakta' && c.felt === 'koen') {
    return { fn: 'red_set_koen', args: { p_person_id: sid, p_koen: c.vaerdi } };
  }
  if (c.art === 'fakta' && c.felt && FELT_FAKTATYPE[c.felt]) {
    const args: Record<string, unknown> = {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid,
      p_faktatype: FELT_FAKTATYPE[c.felt], p_vaerdi: c.vaerdi,
    };
    if (DATE_FELT.has(c.felt)) args.p_date_raw = c.vaerdi;
    if (c.kildeFritekst != null) args.p_kilde_fritekst = c.kildeFritekst;
    return { fn: 'red_upsert_fakta', args };
  }
  // "Forældre ukendt"-markering (docs/reviews/25): find-or-create ét fact pr. person via
  // red_upsert_fakta (re-markering opdaterer grad+kilde på samme slot). Grad = c.vaerdi
  // ('forælder ukendt' | 'ingen forbindelse angivet'); kilde = proveniens. Skriver ALDRIG en kant.
  if (c.art === 'markerForaeldreUkendt') {
    if (!c.vaerdi) return null;
    return { fn: 'red_upsert_fakta', args: {
      p_subjekt_type: 'person', p_subjekt_id: sid,
      p_faktatype: 'forældre_ukendt', p_vaerdi: c.vaerdi,
      p_kilde_fritekst: c.kildeFritekst ?? null } };
  }
  // FJERN markering: tilbagetræk fakta-slottets konklusion (status → 'tilbagetrukket'). IKKE
  // sletOplysning — den re-peger til ældste påstand og genopliver markeringen efter Opdatér (HIGH 2).
  if (c.art === 'tilbagetraekFakta') {
    const raw = (c.factId ?? '').trim();
    const fid = raw === '' ? NaN : Number(raw); // Number('')===0 → afvis tom/blank eksplicit
    if (!Number.isFinite(fid)) return null; // afvis "", "x", NaN — ikke kun null
    return { fn: 'red_tilbagetraek_fakta', args: { p_fact_id: fid } };
  }
  if (c.art === 'narrativ') {
    return { fn: 'red_upsert_narrativ', args: {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid, p_tekst: c.vaerdi,
      p_privat: Boolean(c.payload?.privat),
      p_source_id: (c.payload?.sourceId as number | null | undefined) ?? null,
      p_side: (c.payload?.side as string | null | undefined) ?? null } };
  }
  if (c.art === 'opretKilde') {
    const p = c.payload || {};
    if (!p.titel) return null;
    return { fn: 'red_opret_kilde', args: {
      p_titel: p.titel, p_slags: (p.slags as string | null | undefined) ?? null,
      p_udgave: (p.udgave as string | null | undefined) ?? null,
      p_ekstern: Boolean(p.ekstern ?? false),
      p_aar: (p.aar as number | null | undefined) ?? null } };
  }
  if (c.art === 'relation' || c.art === 'gods' || c.art === 'hverv') {
    const p = c.payload || {};
    return { fn: 'red_relation', args: {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid,
      p_objekt_type: p.objektType, p_objekt_id: p.objektId,
      p_rolle: p.rolle, p_periode_raw: p.periodeRaw ?? null } };
  }
  if (c.art === 'sletRelation') {
    const rid = parsePostgresBigintId(c.relationId);
    if (rid == null) return null;
    return { fn: 'red_slet_relation', args: { p_relation_id: rid } };
  }
  if (c.art === 'tilfoejRelation') {
    const p = c.payload || {};
    return { fn: 'red_tilfoej_relation', args: {
      p_subjekt_id: sid, p_objekt_type: p.objektType, p_objekt_id: Number(p.objektId),
      p_rolle: p.rolle, p_periode_raw: p.periodeRaw ?? null } };
  }
  if (c.art === 'opretUnion') {
    const p = c.payload || {};
    if (p.partnerA == null || p.partnerB == null || !p.type) return null;
    return { fn: 'red_opret_union', args: {
      p_partner_a: Number(p.partnerA), p_partner_b: Number(p.partnerB), p_type: p.type,
      p_ordinal: p.ordinal != null ? Number(p.ordinal) : null } };
  }
  if (c.art === 'tilfoejBarn') {
    const p = c.payload || {};
    if (p.familyId == null || p.barnId == null) return null;
    return { fn: 'red_tilfoej_barn', args: {
      p_family_id: Number(p.familyId), p_barn_id: Number(p.barnId),
      p_rolle: p.rolle || 'barn', p_konfidens: p.konfidens ?? null } };
  }
  if (c.art === 'setFamilieKonfidens') { const b = famLinkBase(c); if (!b) return null;
    return { fn: 'red_set_familie_konfidens', args: { ...b, p_konfidens: c.konfidens ?? null } }; }
  if (c.art === 'sletFamilieLink') { const b = famLinkBase(c); if (!b) return null;
    return { fn: 'red_slet_familie_link', args: b }; }
  if (c.art === 'setFamilieOrdinal') { const b = famLinkBase(c); if (!b || c.ordinal == null) return null;
    return { fn: 'red_set_familie_ordinal', args: { ...b, p_ordinal: c.ordinal } }; }
  if (c.art === 'sammeSom') {
    const p = c.payload || {};
    if (p.aliasId == null || p.objektId == null) return null;
    return { fn: 'red_samme_som', args: { p_alias_id: Number(p.aliasId), p_objekt_id: Number(p.objektId) } };
  }
  if (c.art === 'fjernSammeSom') {
    if (c.relationId == null) return null;
    return { fn: 'red_fjern_samme_som', args: { p_relation_id: Number(c.relationId) } };
  }
  if (c.art === 'ikkeSammeSom') {
    const p = c.payload || {};
    if (p.aId == null || p.bId == null) return null;
    return { fn: 'red_ikke_samme_som', args: { p_a: Number(p.aId), p_b: Number(p.bId) } };
  }
  if (c.art === 'fjernIkkeSammeSom') {
    if (c.relationId == null) return null;
    return { fn: 'red_fjern_ikke_samme_som', args: { p_relation_id: Number(c.relationId) } };
  }
  if (c.art === 'publicerPersoner') {
    const p = c.payload || {};
    const ids = Array.isArray(p.personIds) ? (p.personIds as unknown[]) : null;
    if (!ids || !ids.length || ids.some((id) => id == null || !Number.isFinite(Number(id)))) return null;
    return { fn: 'red_publicer_personer', args: { p_person_ids: ids.map(Number) } };
  }
  if (c.art === 'foraeldrePaastand') { // registrér en udgaves forældrefamilie-påstand (Problem 2)
    const p = c.payload || {};
    if (p.barnId == null || p.familyId == null) return null;
    const args: Record<string, unknown> = { p_barn_id: Number(p.barnId), p_family_id: Number(p.familyId) };
    if (p.sourceId != null) args.p_source_id = Number(p.sourceId);
    if (p.side != null) args.p_side = String(p.side);
    if (p.citat != null) args.p_citat = String(p.citat);
    if (p.kildeFritekst != null) args.p_kilde_fritekst = String(p.kildeFritekst);
    return { fn: 'red_tilfoej_foraeldre_paastand', args };
  }
  if (c.art === 'vaelgForaeldre') { // adjudikér den kanoniske forældrefamilie (Problem 2)
    const p = c.payload || {};
    if (p.assertionId == null) return null;
    const args: Record<string, unknown> = { p_assertion_id: Number(p.assertionId) };
    if (p.konfidens != null) args.p_konfidens = String(p.konfidens);
    return { fn: 'red_vaelg_foraeldre', args };
  }
  if (c.art === 'flytBarn') {
    if (c.familyId == null || c.tilFamilyId == null || c.personId == null || !c.rolle) return null;
    return { fn: 'red_flyt_barn', args: {
      p_fra_family_id: Number(c.familyId), p_til_family_id: Number(c.tilFamilyId),
      p_barn_id: Number(c.personId), p_rolle: c.rolle } };
  }
  // Portræt (p_afbildet_person_id) ELLER objekt-foto (p_objekt_type/p_objekt_id) — aldrig begge
  // (red_upload_media/red_relation håndhæver GDPR-invarianten server-side). p_titel er PÅKRÆVET
  // af RPC'en (intet DEFAULT) — payload skal altid sætte et.
  if (c.art === 'uploadMedia') {
    const p = c.payload || {};
    if (!p.slags || !p.titel || !p.storagePath || !p.mimeType) return null;
    const args: Record<string, unknown> = {
      p_slags: p.slags, p_titel: p.titel, p_storage_path: p.storagePath, p_mime: p.mimeType,
      p_kunstner: p.kunstner ?? null, p_datering: p.datering ?? null,
      p_byte_size: p.byteSize ?? null, p_bredde: p.bredde ?? null, p_hoejde: p.hoejde ?? null,
      p_original_filnavn: p.originalFilnavn ?? null,
      p_rettigheder_status: p.rettighederStatus ?? 'ukendt', p_maa_publiceres: Boolean(p.maaPubliceres),
      p_sha256: p.sha256 ?? null,
    };
    if (p.afbildetPersonId != null) args.p_afbildet_person_id = Number(p.afbildetPersonId);
    else if (p.objektType != null && p.objektId != null) {
      args.p_objekt_type = p.objektType;
      args.p_objekt_id = Number(p.objektId);
    }
    return { fn: 'red_upload_media', args };
  }

  if (c.art === 'tilknytMedia') {
    const mediaId = parsePostgresBigintId(c.mediaId);
    const maalId = parsePostgresBigintId(c.payload?.maalId);
    const maalType = c.payload?.maalType;
    const tilladteMaal = new Set(['person', 'estate', 'coat_of_arms', 'lineage']);
    if (mediaId == null || maalId == null || typeof maalType !== 'string' || !tilladteMaal.has(maalType)) return null;
    const person = maalType === 'person';
    return { fn: 'red_relation', args: {
      p_subjekt_type: person ? 'person' : 'media',
      p_subjekt_id: person ? maalId : mediaId,
      p_objekt_type: person ? 'media' : maalType,
      p_objekt_id: person ? mediaId : maalId,
      p_rolle: 'afbildet',
      p_periode_raw: null,
    } };
  }

if (c.art === 'opdaterMedia') {
  if (c.mediaId == null) return null;
  const p = c.payload || {};
  const args: Record<string, unknown> = { p_media_id: Number(c.mediaId) };
  const felter: Array<[string, string]> = [
    ['titel', 'p_titel'], ['slags', 'p_slags'], ['kunstner', 'p_kunstner'], ['datering', 'p_datering'],
  ];
  for (const [key, arg] of felter) {
    if (Object.prototype.hasOwnProperty.call(p, key)) args[arg] = p[key];
  }
  return { fn: 'red_opdater_media', args };
}
if (c.art === 'genopretMedia') {
  if (c.mediaId == null) return null;
  return { fn: 'red_genopret_media', args: { p_media_id: Number(c.mediaId) } };
}
if (c.art === 'mediaRettigheder') {
  if (c.mediaId == null) return null;
  const p = c.payload || {};
  if (!p.status) return null;
  const args: Record<string, unknown> = {
    p_media_id: Number(c.mediaId),
    p_status: p.status,
    p_maa_publiceres: Boolean(p.maaPubliceres),
  };
  const dokumentation: Array<[string, string]> = [
    ['licens', 'p_licens'],
    ['kildehenvisning', 'p_kildehenvisning'],
    ['gengivelsestilladelse', 'p_gengivelsestilladelse'],
    ['kildeFritekst', 'p_kilde_fritekst'],
  ];
  for (const [key, arg] of dokumentation) {
    const value = p[key];
    if (typeof value === 'string' && value.trim()) args[arg] = value.trim();
  }
  return { fn: 'red_set_media_rettigheder', args };
}
  // Blødt fjern (Slice 0h): sætter upload_status='fjernet', rører aldrig Storage-bytes eller
  // relationen. At AFKOBLE et billede fra én person (uden at slette det andre steder) er derimod
  // bare en almindelig 'sletRelation' på den specifikke afbildet-relation (håndteret ovenfor).
  if (c.art === 'fjernMedia') {
    const mediaId = parsePostgresBigintId(c.mediaId);
    if (mediaId == null) return null;
    return { fn: 'red_fjern_media', args: { p_media_id: mediaId } };
  }
  return null;
}

// Menneskelæselig forhåndsvisning til dry-run-sheet (matcher prototypens kode-blok-stil).
export function describeCall(call: RpcCall): string {
  return `rpc ${call.fn}\n${JSON.stringify(call.args, null, 2)}`;
}

// Forslag → staging (red_suggest). Routing-fallback: ikke-redaktion, eller redaktion på en
// art uden direkte RPC (fx generisk entitets-feltredigering). Bygger ALTID et gyldigt kald.
export function buildSuggestCall(c: Change): RpcCall {
  const fallbackPayload = c.art === 'haendelseStatus'
    ? { haendelseId: c.haendelseId, status: c.status }
    : c.art === 'tilknytMedia'
      ? { ...(c.payload ?? {}), mediaId: c.mediaId }
      : c.art === 'setStoryStatus' || c.art === 'sletStory'
        ? { storyId: c.storyId, storyStatus: c.storyStatus }
        : c.art === 'setStoryKilder'
          ? { storyId: c.storyId, kilder: c.kilder }
          : c.art === 'setFeedPin'
            ? { kortNoegle: c.kortNoegle, handling: c.handling }
            : c.art === 'fjernFeedPin'
              ? { kortNoegle: c.kortNoegle }
              : {};
  const payload = c.art === 'tilknytMedia' || c.payload == null
    ? fallbackPayload
    : c.art === 'opretStory'
      ? { ...c.payload, kilder: c.kilder ?? [] }
      : c.art === 'redigerStory'
        ? { ...c.payload, storyId: c.storyId, kilder: c.kilder ?? [] }
        : c.payload;
  return { fn: 'red_suggest', args: {
    p_art: c.art,
    p_subjekt_type: c.subjektType,
    p_subjekt_id: c.art === 'tilknytMedia'
      ? parsePostgresBigintId(c.mediaId)
      : c.subjektId != null && c.subjektId !== '' ? Number(c.subjektId) : null,
    p_felt: c.felt ?? null,
    p_vaerdi: c.vaerdi ?? null,
    p_kilde_fritekst: c.kildeFritekst ?? null,
    p_payload: payload,
    p_note: null,
  } };
}

// Vælg kald efter rolle: redaktion + kendt art → direkte red_*-RPC; ellers → red_suggest (staging).
export function planCall(c: Change, role: string | undefined): RpcCall {
  const bygget = buildRpcCall(c);
  if (c.art === 'tilknytMedia' && !bygget) throw new Error('Ugyldig medietilknytning.');
  const direct = role === 'redaktion' ? bygget : null;
  return direct ?? buildSuggestCall(c);
}

// dry-run: returnér det planlagte kald (UI viser fn+args). live: udfør via supabase.rpc.
// uploadMedia er særligt: bytes skal lande i Storage FØR RPC'en (Postgres-txn og Storage-upload
// kan ikke dele transaktion). Sker KUN når kaldet reelt går direkte (direkte===true, dvs. rolle
// redaktion) — falder changen igennem til red_suggest (ikke-redaktion) uploades intet, da
// forslags-laget ikke ejer nogen fil-bytes at pege på.
export async function submitChange(c: Change, opts: { dryRun: boolean; role?: string }) {
  const call = planCall(c, opts.role);
  const direkte = call.fn !== 'red_suggest';
  // uploadMedia kan IKKE degradere til red_suggest: forslags-laget gemmer kun p_payload som jsonb,
  // og en rå File-værdi JSON-serialiserer til '{}' (ingen egne enumerable felter) — en sådan
  // "forslag sendt"-kvittering ville lyve. UI'en skjuler allerede knappen for ikke-redaktion
  // (Redaktion.tsx), men denne gate er den robuste, ikke UI-afhængige grænse (fejler tydeligt
  // fremfor at oprette et korrupt forslag med falsk succes).
  if (c.art === 'uploadMedia' && !direkte) {
    throw new Error('Medieupload kræver redaktør-rettigheder — kan ikke sendes som forslag.');
  }
  if (opts.dryRun) return { dryRun: true as const, call, direkte };
  if (c.art === 'uploadMedia') {
    const p = c.payload || {};
    if (!p.file || !p.storagePath) throw new Error('Mangler fil eller sti til upload');
    await performUpload(p.file as Blob, String(p.storagePath));
  }
  const { data, error } = await supabase.rpc(call.fn, call.args);
  if (error) throw new Error(error.message);
  // red_upload_media opretter ALTID rækken som upload_status='kladde'; først når bytes reelt ligger
  // i Storage (lige udført ovenfor) er det sandt at bekræfte 'klar' — derfor et separat RPC-kald.
  if (c.art === 'uploadMedia') {
    const { error: bekraeftError } = await supabase.rpc('red_bekraeft_media_upload', { p_media_id: data });
    if (bekraeftError) throw new Error(bekraeftError.message);
    // Billedstørrelser Slice B2: thumb+medium er selvstændige størrelsestrin (media_variant),
    // ikke en del af red_upload_media selv — hver uploades og registreres uafhængigt af de andre.
    const varianter = (c.payload?.varianter ?? []) as Array<{
      tier: string; file: Blob; storagePath: string; mimeType: string; byteSize: number; bredde: number; hoejde: number;
    }>;
    await Promise.all(varianter.map(async (v) => {
      await performUpload(v.file, v.storagePath);
      const { error: variantError } = await supabase.rpc('red_registrer_media_variant', {
        p_media_id: data, p_tier: v.tier, p_storage_path: v.storagePath,
        p_mime: v.mimeType, p_byte_size: v.byteSize, p_bredde: v.bredde, p_hoejde: v.hoejde,
      });
      if (variantError) throw new Error(variantError.message);
    }));
  }
  return { dryRun: false as const, call, direkte, result: data };
}

// PostgREST/Postgres-fejl → dansk UI-tekst (spec §9). Fald tilbage til rå besked.
export function oversaetFejl(message: string): string {
  if (/kun redaktion/i.test(message)) return 'Kræver redaktør-rettigheder.';
  if (/medie med samme indhold findes allerede/i.test(message)) return "Billedet findes allerede i biblioteket — brug 'Tilknyt eksisterende' i stedet.";
  if (/allerede tilknyttet dette subjekt/i.test(message)) return 'Mediet er allerede tilknyttet dette subjekt.';
  if (/duplicate key|unique/i.test(message)) return 'Findes allerede.';
  if (/not configured|ikke konfigureret/i.test(message)) return 'Ingen forbindelse til basen.';
  if (/kan kun genoprette et fjernet medie/i.test(message)) return 'Mediet kan kun genoprettes, når det er fjernet.';
  if (/slags kan ikke ryddes/i.test(message)) return 'Slags kan ikke ryddes.';
  if (/afbildet skal gå person.*media|person kan ikke stå på objekt-siden|gdpr-gating/i.test(message)) {
    return 'En person skal stå på subjekt-siden ved billedtilknytning.';
  }
  return message;
}
