// Domæne-typer for den flade visningsmodel (svarer til SQL-viewet person_display).
// Person-id er bigint i basen → konverteres ALTID til streng internt (README §8).

// Rå rækker fra Supabase (kun de felter loaderen selecter).
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
};
export type RawNarrative = {
  subjekt_id: number | string;
  subjekt_type: string;
  tekst: string | null;
  privat: boolean | null;
};
export type RawExtId = {
  person_id: number | string;
  source_id: number | string;
  linje: string | null;
  nr: number | null;
};
export type RawLineage = {
  source_id: number | string;
  kode: string | null;
  navn: string | null;
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
export type RawEstate = { id: number | string; navn: string | null; slags: string | null };
export type RawOrg = { id: number | string; navn: string | null; slags: string | null };
export type RawMedia = { person_id?: number | string | null; [k: string]: unknown };

// Mellem-form fra loadFromSupabase (FØR buildModel udleder parentId/spouse).
export type Union = {
  id: string; // 'f' + family_id
  p1: string;
  p2: string | null;
  p2_name: string | null;
  year: number | null;
};
export type ParentChild = { child: string; parent: string; union: string };

// En person i appens visningsmodel.
export type AppPerson = {
  id: string;
  name: string;
  born: number | null;
  died: number | null;
  years: string; // ordret: "* 1640", "† 1708", "1640–1708"
  title: string;
  bio: string;
};

// Db = output af loadFromSupabase; persons mangler stadig parentId/spouse.
export type Db = {
  persons: AppPerson[];
  unions: Union[];
  parentChild: ParentChild[];
};

// Person beriget af buildModel (parentId + spouse afledt).
export type ModelPerson = AppPerson & {
  parentId: string | null;
  spouse: string;
};

// Side-indekser fra buildModel — i React var det instans-felter (_childIdx osv.);
// i Zustand SKAL de gemmes eksplicit som state (advisor 2026-06-23).
export type ModelIndexes = {
  spousesBy: Record<string, { id: string | null; name: string }[]>;
  childIdx: Record<string, Set<string>>;
  parentsByChild: Record<string, string[]>;
  childrenByUnion: Record<string, Record<string, string[]>>;
  unionById: Record<string, Union>;
};

export type Model = {
  persons: ModelPerson[];
  byId: Record<string, ModelPerson>;
  indexes: ModelIndexes;
};

// Aux-indekser (kilder, embeder, godser, linjer, medier) pr. person.
export type SourceRef = { ref: string; work: string };
export type EstateRef = { navn: string; period: string };
export type OfficeRef = { label: string; period: string; _y: number };
export type OwnerRef = { personId: string; period: string; _y: number };
export type LinjeEntry = { linje: string; count: number; headId: string | null; navn: string | null };
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
};
