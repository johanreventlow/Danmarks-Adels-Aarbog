// Domæne-typer for den flade visningsmodel (svarer til SQL-viewet person_display).
// Person-id er bigint i basen → konverteres ALTID til streng internt (README §8).
//
// De DELTE typer (Model/Db/Geo/collapse m.fl.) bor nu i @daa/core og re-eksporteres
// herfra, så eksisterende imports fra './types' virker uændret. Kun mobil-specifikke
// typer (Aux, Raw-rækker loaderen alene bruger, media-typer, normaliserings-helpers)
// defineres lokalt. Core's Model er et SUPERSET (valgfrie lag som lineage/geo); mobilen sætter 6e-lagene
// (lineage, sourcesBy, udgaver, linjeRaekkerBy, bogNrBy) via data/udgaveLag.ts.
import { KONFIDENS_VALUES } from '@daa/core';
import type { Koen, Konfidens, SourceRef } from '@daa/core';

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
  visning_floruit?: string | null;
  visning_titel: string | null;
  koen: string | null;
  privat: boolean | null;
  levende?: boolean | null;
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
  kvalifikator?: { primaer?: boolean } | null;
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
  byte_size?: number | null;
  bredde?: number | null;
  hoejde?: number | null;
  created_at?: string | null;
  primaer?: boolean;
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
// id = godsets id (samler samme gods i flere rækker); personId = relationens rå subjekt-id (før samme_som-foldningen),
// som @daa/core's godserIUdgave slår rækkens udgave op på — samme form som web's PersonEstate.
export type EstateRef = { id: string; navn: string; period: string; personId: string };
// rolle: rå relation.rolle (statuslinjens hof-/rangtitel-algoritme læser den; label er kun visning)
export type OfficeRef = { label: string; period: string; _y: number; rolle: string | null };
// period: perioden uden parenteser (stripParen); periodeRaw: bogens tekst, som ejerrækken (byggEjerraekke) tager.
export type OwnerRef = { personId: string; period: string; periodeRaw: string; _y: number };
// ejerIds: kanoniske ejer-id'er; ownerCount: antal forskellige af dem (før skærmens omtælling mod modellen).
export type EstateListEntry = { id: string; navn: string; slags: string; ownerCount: number; ejerIds: string[] };

// Linjerne bor ikke her men på modellen (model.lineage, 6e): én nøgle pr. kanonisk linje på tværs af udgaver.
export type Aux = {
  // Bogens opslag, ellers citations-proveniensen (ægtefæller). Personsiden tager model.sourcesBy først, som web.
  sourcesBy: Record<string, SourceRef[]>;
  estatesBy: Record<string, EstateRef[]>;
  officesBy: Record<string, OfficeRef[]>;
  mediaBy: Record<string, RawMedia[]>;
  mediaById: Record<string, RawMedia>; // alle media-rækker, id-nøglet (billeder-i-narrativer 2026-07-05, Slice C)
  mediaByObjekt: Record<string, RawMedia[]>; // »estate:12« / »coat_of_arms:3« → billeder (media→objekt, 'afbildet')
  ownersByEstate: Record<string, OwnerRef[]>;
  estateList: EstateListEntry[];
  estateById: Record<string, { id: string; navn: string; slags: string; stedId: string | null }>;
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
  vaabenListe: { id: string; blasonering: string; note: string }[]; // dansk-sorteret (redaktionen)
  vaaben: { id: string; blasonering: string; note: string }[]; // id-orden (våbensiden; første = hovedvåbnet)
};
