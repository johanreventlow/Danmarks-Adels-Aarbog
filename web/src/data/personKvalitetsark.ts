// Dataadapter til personers OCR-kvalitetsark (task 7 i
// docs/superpowers/plans/2026-07-26-person-ocr-kvalitetsark.md). Bevidst adskilt fra
// redaktionWrite.ts's generiske Change-union — dette er en fokuseret, smal korrektionsflade
// (kun red_person_grid/red_ret_ocr_felt/red_ocr_historik), ikke endnu en art i den flade.
//
// bigint-kolonner (person_id, source_id, *_assertion_id, kanonisk_person_id,
// change_set_id) mappes ALTID til string — se @daa/core/src/ocrKvalitet.ts's header-kommentar:
// JS's number kan ikke sikkert rumme store bigint-værdier, og Postgres/PostgREST leverer
// bigint uden garanteret tekst-cast fra red_person_grid()/red_ret_ocr_felt().
import { supabase } from '../supabase';
import { getAll } from '@daa/core';
import type { OcrFelt, OcrReviewStatus, PersonKvalitetsarkRow } from '@daa/core';
import { oversaetFejl } from './redaktionWrite';

const OCR_FELTER: readonly OcrFelt[] = ['navn', 'foedsel', 'doed', 'koen'];

// --- Kontraktfejl ved grænsen ---
// Kastes hvis red_person_grid()/red_ret_ocr_felt() leverer en række der ikke overholder
// den kontrakt, kvalitetsarket bygger på — fejler tydeligt frem for at rendere en tavs,
// forkert celle eller et redigerbarheds-flag der stille falder tilbage til "false".
class OcrGridKontraktFejl extends Error {
  constructor(message: string) {
    super(`red_person_grid-kontraktbrud: ${message}`);
    this.name = 'OcrGridKontraktFejl';
  }
}

type BigintLike = number | string | null | undefined;

function bigintTilString(v: BigintLike, felt: string, personId: unknown): string {
  if (v === null || v === undefined) {
    throw new OcrGridKontraktFejl(`${felt} mangler (person_id=${String(personId)})`);
  }
  return String(v);
}

function bigintTilStringEllerNull(v: BigintLike): string | null {
  return v === null || v === undefined ? null : String(v);
}

// source_id kan reelt være NULL: external_anchor er en LEFT JOIN person_external_id …
// GROUP BY p.id i red_person_grid() (schema.sql), så en person UDEN nogen
// person_external_id-række stadig får én grid-række, blot med source_id=NULL (og
// blokarsag 'ingen_importanker' i kan_rettes/blokarsager). @daa/core's
// PersonKvalitetsarkRow.sourceId er typet som `string` (ikke `string | null`) — den type
// ejes af Task 6 og er uden for denne opgaves scope at ændre. At kaste her ville i stedet
// vælte HELE griddet på én ramt person, i modstrid med Global Constraints "Alle personer
// er en permanent first-class view" og "Ambiguous rows remain readable". Vi falder derfor
// bevidst tilbage til tom streng frem for at kaste — se ikke-afklaret bekymring i
// task-7-report.md for Task 8 (UI bør behandle en tom sourceId som "intet importanker").
function bigintTilStringMedTomFallback(v: BigintLike): string {
  return v === null || v === undefined ? '' : String(v);
}

// Raw RPC-række (snake_case) — spejler RETURNS TABLE i red_person_grid() (schema.sql).
type RawPersonGridRow = {
  person_id: BigintLike;
  import_key: string | null;
  record_key: string | null;
  source_id: BigintLike;
  source_titel: string | null;
  source_udgave: string | null;
  linje: string | null;
  nr: number | null;
  slaegtled: number | null;
  navn: string;
  navn_assertion_id: BigintLike;
  foedsel_raw: string | null;
  foedsel_min: string | null;
  foedsel_max: string | null;
  foedsel_qualifier: string | null;
  foedsel_assertion_id: BigintLike;
  doed_raw: string | null;
  doed_min: string | null;
  doed_max: string | null;
  doed_qualifier: string | null;
  doed_assertion_id: BigintLike;
  input_fingerprint: Record<string, string> | null;
  importeret: Record<string, Record<string, unknown>> | null;
  korrigeret: Record<string, Record<string, unknown> | null> | null;
  ocr_context: Record<string, string | null> | null;
  kilde_side: Record<string, string | null> | null;
  koen: string | null;
  levende: boolean | null;
  privat: boolean | null;
  staged: boolean | null;
  person_status: string | null;
  kanonisk_person_id: BigintLike;
  samme_som_status: string | null;
  antal_titler: number;
  antal_familier: number;
  antal_relationer: number;
  antal_kilde_assertions: number;
  qa_koder: unknown;
  qa_alvor: 'fejl' | 'advarsel' | 'info' | null;
  review_status: Partial<Record<OcrFelt, OcrReviewStatus>> | null;
  kan_rettes: unknown;
  blokarsager: Partial<Record<OcrFelt, string>> | null;
};

function erKanRettesGyldig(v: unknown): v is Record<OcrFelt, boolean> {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) return false;
  return OCR_FELTER.every((felt) => typeof (v as Record<string, unknown>)[felt] === 'boolean');
}

function mapPersonKvalitetsarkRow(raw: RawPersonGridRow | null): PersonKvalitetsarkRow {
  if (!raw) throw new OcrGridKontraktFejl('rækken mangler helt');
  if (raw.person_id === null || raw.person_id === undefined) {
    throw new OcrGridKontraktFejl('person_id mangler i rækken');
  }
  if (!Array.isArray(raw.qa_koder)) {
    throw new OcrGridKontraktFejl(`qa_koder er ikke en liste (person_id=${String(raw.person_id)})`);
  }
  if (!erKanRettesGyldig(raw.kan_rettes)) {
    throw new OcrGridKontraktFejl(
      `kan_rettes mangler eller dækker ikke alle felter (${OCR_FELTER.join(', ')}) (person_id=${String(raw.person_id)})`,
    );
  }

  return {
    personId: bigintTilString(raw.person_id, 'person_id', raw.person_id),
    importKey: raw.import_key,
    recordKey: raw.record_key,
    sourceId: bigintTilStringMedTomFallback(raw.source_id),
    sourceTitel: raw.source_titel,
    sourceUdgave: raw.source_udgave,
    linje: raw.linje,
    nr: raw.nr,
    slaegtled: raw.slaegtled,
    personStatus: raw.person_status,
    navn: raw.navn,
    navnAssertionId: bigintTilStringEllerNull(raw.navn_assertion_id),
    foedselRaw: raw.foedsel_raw,
    foedselMin: raw.foedsel_min,
    foedselMax: raw.foedsel_max,
    foedselQualifier: raw.foedsel_qualifier,
    foedselAssertionId: bigintTilStringEllerNull(raw.foedsel_assertion_id),
    doedRaw: raw.doed_raw,
    doedMin: raw.doed_min,
    doedMax: raw.doed_max,
    doedQualifier: raw.doed_qualifier,
    doedAssertionId: bigintTilStringEllerNull(raw.doed_assertion_id),
    koen: raw.koen,
    levende: Boolean(raw.levende),
    privat: Boolean(raw.privat),
    staged: Boolean(raw.staged),
    kanoniskPersonId: bigintTilStringEllerNull(raw.kanonisk_person_id),
    sammeSomStatus: raw.samme_som_status,
    antalTitler: raw.antal_titler,
    antalFamilier: raw.antal_familier,
    antalRelationer: raw.antal_relationer,
    antalKildeAssertions: raw.antal_kilde_assertions,
    qaKoder: raw.qa_koder as string[],
    qaAlvor: raw.qa_alvor,
    reviewStatus: raw.review_status ?? {},
    kanRettes: raw.kan_rettes,
    blokarsager: raw.blokarsager ?? {},
    ocrContext: raw.ocr_context ?? {},
    kildeSide: raw.kilde_side ?? {},
    importeret: raw.importeret ?? {},
    korrigeret: raw.korrigeret ?? {},
    inputFingerprint: raw.input_fingerprint ?? {},
  };
}

// Ét RPC-kald pr. side (getAll pagineres via .range på red_person_grid()'s
// set-returnerende resultat) — aldrig ét kald pr. person. red_person_grid()'s afsluttende
// SELECT har INGEN ORDER BY (verificeret mod schema.sql), så uden en eksplicit .order() her
// giver Postgres ingen garanti for stabil rækkefølge mellem to separate .range()-forespørgsler
// — en side-2-forespørgsel kunne i teorien springe over eller gentage rækker. .order('person_id')
// gør pagineringen deterministisk (samme mønster som fx model.ts's .order('id') før .range()).
export async function fetchPersonKvalitetsark(): Promise<PersonKvalitetsarkRow[]> {
  const rows = await getAll<RawPersonGridRow>(() =>
    supabase.rpc('red_person_grid').order('person_id'));
  return rows.map(mapPersonKvalitetsarkRow);
}

// --- red_ocr_historik (lazy per-felt historik) ---

export type OcrHistorikEntry = {
  changeSetId: string;
  changedAt: string;
  actorNavn: string | null;
  operation: string | null;
  foer: Record<string, unknown> | null;
  efter: Record<string, unknown> | null;
};

type RawOcrHistorikRow = {
  change_set_id: BigintLike;
  changed_at: string;
  actor_navn: string | null;
  operation: string | null;
  foer: Record<string, unknown> | null;
  efter: Record<string, unknown> | null;
};

export async function fetchOcrHistorik(
  importKey: string,
  recordKey: string,
  felt: OcrFelt,
): Promise<OcrHistorikEntry[]> {
  const { data, error } = await supabase.rpc('red_ocr_historik', {
    p_import_key: importKey,
    p_record_key: recordKey,
    p_felt: felt,
  });
  if (error) throw error;
  // Rækkefølgen (nyeste først) kommer allerede fra SQL'ens ORDER BY — omsorteres ikke her.
  const rows = (data ?? []) as RawOcrHistorikRow[];
  return rows.map((r) => ({
    changeSetId: bigintTilString(r.change_set_id, 'change_set_id', r.change_set_id),
    changedAt: r.changed_at,
    actorNavn: r.actor_navn,
    operation: r.operation,
    foer: r.foer,
    efter: r.efter,
  }));
}

// --- red_ret_ocr_felt (den smalle, atomare korrektions-mutation) ---

export async function retOcrFelt(input: {
  personId: string;
  importKey: string;
  recordKey: string;
  felt: OcrFelt;
  inputFingerprint: string;
  korrigeret: Record<string, unknown> | null;
  status: 'rettet' | 'godkendt' | 'udskudt';
  actorNavn?: string;
}): Promise<PersonKvalitetsarkRow> {
  const { data, error } = await supabase.rpc('red_ret_ocr_felt', {
    p_person_id: Number(input.personId),
    p_import_key: input.importKey,
    p_record_key: input.recordKey,
    p_felt: input.felt,
    p_input_fingerprint: input.inputFingerprint,
    p_korrigeret: input.korrigeret,
    p_status: input.status,
    p_actor_navn: input.actorNavn ?? null,
  });
  if (error) throw error;
  return mapPersonKvalitetsarkRow(data as RawPersonGridRow);
}

// --- Fejloversættelse ---
//
// Den fulde, verificerede liste af OCR_*-koder fra schema.sql (red_ret_ocr_felt /
// red_ocr_historik). Enhver anden kode/besked rammer det generiske fallback-spor —
// aldrig en tavs, uoversat fejl i redaktørfladen.
const OCR_FEJLTEKST: Record<string, string> = {
  OCR_ROLE_FORBIDDEN: 'Kræver redaktør-rettigheder for at rette OCR-felter.',
  OCR_FIELD_INVALID: 'Feltet er ikke et gyldigt OCR-rettefelt (navn, fødsel, død eller køn).',
  OCR_VALUE_INVALID: 'Den indtastede værdi er ugyldig for dette felt og denne status.',
  OCR_IMPORT_ANCHOR_AMBIGUOUS:
    'Personen har ikke en entydig kildeforankring — rettelse kan ikke foretages sikkert her. Brug den almindelige editor i stedet.',
  OCR_PERSON_NOT_FOUND: 'Personen blev ikke fundet, eller matcher ikke kilde-posten.',
  OCR_ASSERTION_AMBIGUOUS:
    'Feltet peger på mere end én — eller ingen — kildebelagt påstand. Brug den almindelige editor til at afklare dette først.',
  OCR_FINGERPRINT_STALE:
    'Kildeteksten er ændret, siden du hentede rækken. Genindlæs kvalitetsarket, og prøv igen.',
};

const OCR_KODE_RE = /OCR_[A-Z_]+/;

function udtraekFejlbesked(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string') return error;
  if (error && typeof error === 'object' && 'message' in error) {
    const m = (error as { message?: unknown }).message;
    if (typeof m === 'string') return m;
  }
  return String(error);
}

export function oversaetOcrFejl(error: unknown): string {
  const message = udtraekFejlbesked(error);
  const kodeMatch = OCR_KODE_RE.exec(message);
  const kode = kodeMatch?.[0];
  if (kode && kode in OCR_FEJLTEKST) return OCR_FEJLTEKST[kode];
  // Ikke en OCR_*-kode — kan stadig være en kendt generisk redaktionsfejl (fx den delte
  // rolle-guard 'Kun redaktion', som red_person_grid() selv rejser uden OCR_-præfiks).
  // Genbruger redaktionWrite.ts's egen oversætter frem for at duplikere dens mønstre.
  const generisk = oversaetFejl(message);
  if (generisk !== message) return generisk;
  return `Ukendt fejl ved OCR-rettelse: ${message}`;
}
