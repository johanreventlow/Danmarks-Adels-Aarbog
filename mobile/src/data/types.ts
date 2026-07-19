// Domæne-typer for den flade visningsmodel (svarer til SQL-viewet person_display).
// Person-id er bigint i basen → konverteres ALTID til streng internt (README §8).
//
// De DELTE typer (Model/Db/Geo/collapse m.fl.) bor nu i @daa/core og re-eksporteres
// herfra, så eksisterende imports fra './types' virker uændret. Kun mobil-specifikke
// typer (Aux, Raw-rækker loaderen alene bruger, media-typer, normaliserings-helpers)
// defineres lokalt. Core's Model er et SUPERSET (valgfrie web-lag som lineage/geo) —
// mobil sætter dem ikke, hvilket er additivt sikkert.
import { KONFIDENS_VALUES } from '@daa/core';
import type { Koen, Konfidens, SourceRef, LinjeEntry } from '@daa/core';

export { KONFIDENS_VALUES, KONFIDENS_RANK } from '@daa/core';
export type {
  RawExtId,
  RawLineage,
  RawEstate,
  RawPlace,
  RawFact,
  Union,
  ParentChild,
  Koen,
  Konfidens,
  AppPerson,
  Db,
  SameAsEdge,
  Provenance,
  QuarantineNote,
  CollapseResult,
  ModelPerson,
  ModelIndexes,
  Model,
  Lineage,
  SourceRef,
  LinjeEntry,
  GeoKind,
  GeoPoint,
  Geo,
} from '@daa/core';

// Rå rækker fra Supabase (kun de felter loaderen selecter) — mobil-specifikke.
export type RawPerson = {
  id: number | string;
  visning_navn: string | null;
  visning_fuldt_navn: string | null;
  visning_foedt: string | null;
  visning_doed: string | null;
  visning_titel: string | null;
  koen: string | null;
  privat: boolean | null;
};
export type RawFamily = { id: number | string; type: string | null };
export type RawMember = {
  family_id: number | string;
  person_id: number | string;
  rolle: string | null;
  ordinal: number | null;
  konfidens?: string | null;
};
export type RawNarrative = {
  id: number;
  subjekt_id: number | string;
  subjekt_type: string;
  tekst: string | null;
  privat: boolean | null;
  source_id: number | null;
};
export type RawSource = {
  id: number | string;
  slags: string | null;
  titel: string | null;
  udgave: string | null;
  aar: number | null;
  ekstern: string | null;
};
export type RawRelation = {
  subjekt_type: string;
  subjekt_id: number | string;
  objekt_type: string;
  objekt_id: number | string;
  rolle: string | null;
  periode_raw: string | null;
};
export type RawTextMention = {
  kilde_type: string;
  kilde_id: number | string;
  maal_type: string;
  maal_id: number | string;
};
export type RawOrg = { id: number | string; navn: string | null; slags: string | null };
// Media-række (mediehåndtering Slice 0). person_id findes IKKE i skemaet — kobling til person
// sker via relation (person→media, rolle 'afbildet'); se buildAux.mediaBy.
export type RawMedia = {
  id: number | string;
  slags?: string | null;
  titel?: string | null;
  kunstner?: string | null;
  datering?: string | null;
  storage_path?: string | null;
  mime_type?: string | null;
  thumb_storage_path?: string | null; // billedstørrelser 2026-07-05, Slice B3 (fra media_variant, tier='thumb')
  medium_storage_path?: string | null; // billedstørrelser 2026-07-05, Slice C (fra media_variant, tier='medium')
  upload_status?: string | null;
  maa_publiceres?: boolean | null;
  rettigheder_status?: string | null;
  [k: string]: unknown;
};
export type RawArms = { id: number | string; blasonering: string | null; note: string | null };

// Normalisér rå streng-værdier fra basen til de typede unioner (ukendt → null).
export function normalizeKonfidens(k: string | null | undefined): Konfidens {
  return k != null && (KONFIDENS_VALUES as readonly string[]).includes(k) ? (k as Konfidens) : null;
}
export function normalizeKoen(k: string | null | undefined): Koen {
  return k === 'mand' || k === 'kvinde' ? k : null;
}

// Aux-indekser (kilder, embeder, godser, linjer, medier) pr. person — mobil-specifik.
export type EstateRef = { navn: string; period: string };
export type OfficeRef = { label: string; period: string; _y: number };
export type OwnerRef = { personId: string; period: string; _y: number };
export type EstateListEntry = { id: string; navn: string; ownerCount: number };

export type Aux = {
  sourcesBy: Record<string, SourceRef[]>;
  estatesBy: Record<string, EstateRef[]>;
  officesBy: Record<string, OfficeRef[]>;
  mediaBy: Record<string, RawMedia[]>;
  mediaById: Record<string, RawMedia>; // alle media-rækker, id-nøglet (billeder-i-narrativer 2026-07-05, Slice C)
  ownersByEstate: Record<string, OwnerRef[]>;
  estateList: EstateListEntry[];
  estateById: Record<string, { id: string; navn: string; slags: string }>;
  linjeByPerson: Record<string, string[]>; // flere linjer pr. person (en collapsed grundlægger hører til flere)
  linjeList: LinjeEntry[];
  linjeNavn: Record<string, string>; // linje-kode ('I'..) → fuldt navn ('Den holstenske linje')
  kildeListe: { id: string; titel: string; slags: string; udgave: string }[];
  orgListe: { id: string; navn: string; slags: string }[];
  medieListe: {
    id: string; titel: string; slags: string; kunstner: string; datering: string;
    uploadStatus: string; maaPubliceres: boolean; rettighederStatus: string;
    antalAfbildet: number; antalMentions: number;
    storagePath: string; thumbStoragePath: string; mimeType: string;
    koeer: import('./redaktionRead').MedieKoe[];
  }[];
  medieKoeTaellere: Record<import('./redaktionRead').MedieKoe, number>;
  godsListe: { id: string; navn: string; slags: string; ownerCount: number }[];
  vaabenListe: { id: string; blasonering: string; note: string }[];
};
