// Domæne-typer for den flade visningsmodel (svarer til SQL-viewet person_display).
// Person-id er bigint i basen → konverteres ALTID til streng internt (README §8).
//
// De DELTE typer (Model/Db/Geo/collapse m.fl.) bor nu i @daa/core og re-eksporteres
// herfra, så eksisterende imports fra './types' virker uændret. Kun web-specifikke
// typer (Aux, Raw-rækker loaderen alene bruger, normaliserings-helpers) defineres lokalt.
import { KONFIDENS_VALUES } from '@daa/core';
import type { Geo, Koen, Konfidens, Model, SourceRef, LinjeEntry } from '@daa/core';

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

// Web-specifik udvidelse af den delte Model (review 27 P3, "lazy geo-kæde"): loadModel()
// starter geo tom (EMPTY_GEO) og vedhæfter denne closure, så place+fact først hentes ved
// første kort-brug. Core-typen (app-agnostisk) kender ikke loadGeo — kontrakten hører hjemme
// her, ikke i @daa/core.
export type AppModel = Model & { loadGeo: () => Promise<Geo> };

// Rå rækker fra Supabase (kun de felter loaderen selecter) — web-specifikke.
export type RawPerson = {
  id: number | string;
  visning_navn: string | null;
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
  subjekt_id: number | string;
  subjekt_type: string;
  tekst: string | null;
  privat: boolean | null;
};
export type RawSource = {
  id: number | string;
  slags: string | null;
  titel: string | null;
  udgave: string | null;
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
export type RawOrg = { id: number | string; navn: string | null; slags: string | null };
export type RawMedia = { person_id?: number | string | null; [k: string]: unknown };
export type RawArms = { id: number | string; blasonering: string | null; note: string | null };

// Normalisér rå streng-værdier fra basen til de typede unioner (ukendt → null).
export function normalizeKonfidens(k: string | null | undefined): Konfidens {
  return k != null && (KONFIDENS_VALUES as readonly string[]).includes(k) ? (k as Konfidens) : null;
}
export function normalizeKoen(k: string | null | undefined): Koen {
  return k === 'mand' || k === 'kvinde' ? k : null;
}

// Aux-indekser (kilder, embeder, godser, linjer, medier) pr. person — web-specifik.
export type EstateRef = { navn: string; period: string };
export type OfficeRef = { label: string; period: string; _y: number };
export type OwnerRef = { personId: string; period: string; _y: number };
export type EstateListEntry = { id: string; navn: string; ownerCount: number };

export type Aux = {
  sourcesBy: Record<string, SourceRef[]>;
  estatesBy: Record<string, EstateRef[]>;
  officesBy: Record<string, OfficeRef[]>;
  mediaBy: Record<string, RawMedia[]>;
  ownersByEstate: Record<string, OwnerRef[]>;
  estateList: EstateListEntry[];
  estateById: Record<string, { id: string; navn: string; slags: string }>;
  linjeByPerson: Record<string, string>;
  linjeList: LinjeEntry[];
  linjeNavn: Record<string, string>; // linje-kode ('I'..) → fuldt navn ('Den holstenske linje')
  kildeListe: { id: string; titel: string; slags: string; udgave: string }[];
  orgListe: { id: string; navn: string; slags: string }[];
  medieListe: { id: string; titel: string; slags: string; kunstner: string; datering: string }[];
  godsListe: { id: string; navn: string; slags: string; ownerCount: number }[];
  vaabenListe: { id: string; blasonering: string; note: string }[];
};
