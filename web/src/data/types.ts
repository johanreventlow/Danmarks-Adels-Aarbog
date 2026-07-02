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
  konfidens?: string | null;
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
export type RawArms = { id: number | string; blasonering: string | null; note: string | null };

// Mellem-form fra loadFromSupabase (FØR buildModel udleder parentId/spouse).
export type Union = {
  id: string; // 'f' + family_id
  p1: string;
  p2: string | null;
  p2_name: string | null;
  year: number | null;
};
export type ParentChild = { child: string; parent: string; union: string; konfidens?: Konfidens };

// Køn — normaliseret fra rådata ('mand'/'kvinde'/'ukendt'/null) til det slægtskabs-
// finderen bruger til kønsbestemte etiketter. null = ukendt → kønsneutral fallback.
export type Koen = 'mand' | 'kvinde' | null;

// Konfidens på et slægtskabs-link (family_member.konfidens). Stærk→svag; null = uangivet
// (intet udsagn). Slægtskabsfinderen flager stien hvis den går gennem et svagt led.
export type Konfidens = 'sikker' | 'sandsynlig' | 'formodet' | 'omstridt' | null;

// Gyldige konfidens-værdier i svagest→stærkest-rækkefølge (spejler family_member.konfidens-
// CHECK i schema.sql). Rang AFLEDES af rækkefølgen, så ordningen kun lever ét sted.
export const KONFIDENS_VALUES = ['omstridt', 'formodet', 'sandsynlig', 'sikker'] as const;
export const KONFIDENS_RANK: Record<string, number> = Object.fromEntries(
  KONFIDENS_VALUES.map((v, i) => [v, i]),
);

// Normalisér rå streng-værdier fra basen til de typede unioner (ukendt → null).
export function normalizeKonfidens(k: string | null | undefined): Konfidens {
  return k != null && (KONFIDENS_VALUES as readonly string[]).includes(k) ? (k as Konfidens) : null;
}
export function normalizeKoen(k: string | null | undefined): Koen {
  return k === 'mand' || k === 'kvinde' ? k : null;
}

// En person i appens visningsmodel.
export type AppPerson = {
  id: string;
  name: string;
  born: number | null;
  died: number | null;
  years: string; // ordret: "* 1640", "† 1708", "1640–1708"
  title: string;
  bio: string;
  privat: boolean;
  koen?: Koen; // valgfri: ældre fixtures/seed mangler den → behandles som ukendt
};

// Db = output af loadFromSupabase; persons mangler stadig parentId/spouse.
export type Db = {
  persons: AppPerson[];
  unions: Union[];
  parentChild: ParentChild[];
};

// samme_som-collapse (frontend identitets-projektion). Spejl af mobile — se
// docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md. Kanterne er retningsbestemte
// (subjekt=alias, objekt=kanonisk); afklarede identiteter foldes, konflikter karantæneres.
export type SameAsEdge = { alias: string; canonical: string; konfidens?: Konfidens };
export type Provenance = { personId: string; linje: string | null; nr: number | null };
export type QuarantineNote = { members: string[]; reason: string };
export type CollapseResult = {
  db: Db;
  canonicalIdById: Record<string, string>; // ETHVERT medlems-id → kanonisk id
  mergedFrom: Record<string, Provenance[]>; // kanonisk id → alle kilde-poster
  quarantined: QuarantineNote[];
};

// Person beriget af buildModel (parentId + spouse afledt).
export type ModelPerson = AppPerson & {
  parentId: string | null;
  spouse: string;
  mergedFrom?: Provenance[]; // sat efter collapse: alle kilde-poster hvis personen er foldet
};

// Side-indekser fra buildModel — i React var det instans-felter (_childIdx osv.);
// i Zustand SKAL de gemmes eksplicit som state (advisor 2026-06-23).
export type ModelIndexes = {
  spousesBy: Record<string, { id: string | null; name: string }[]>;
  childIdx: Record<string, Set<string>>;
  parentsByChild: Record<string, string[]>;
  childrenByUnion: Record<string, Record<string, string[]>>;
  unionById: Record<string, Union>;
  // Konfidens pr. forælder→barn-kant, nøgle `${child}|${parent}`. Bruges af slægtskabs-
  // finderen til at finde det svageste led på en sti. Mangler kant = uangivet.
  konfByEdge: Record<string, Konfidens>;
};

export type Model = {
  persons: ModelPerson[];
  byId: Record<string, ModelPerson>;
  indexes: ModelIndexes;
  // Lineage (grene I–V) — valgfrit: udfyldes af loadModel når person_external_id/lineage
  // er tilgængelige; undefined = graceful degradation (ingen linje-chips/badge).
  lineage?: Lineage;
  // "Kilde i Aarbogen"-referencer pr. person (§ + trykt værk + "Linje X, nr. N"). Valgfrit.
  sourcesBy?: Record<string, SourceRef[]>;
};

// Linje-projektion pr. slægt (grene). byPerson: person_id → linje-kode; list: chips-data
// (kode, antal, stamfader=headId, fuldt navn); navn: kode → fuldt navn.
export type Lineage = {
  byPerson: Record<string, string[]>; // flere linjer pr. person (en collapsed grundlægger hører til flere)
  list: LinjeEntry[];
  navn: Record<string, string>;
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
  kildeListe: { id: string; titel: string; slags: string; udgave: string }[];
  orgListe: { id: string; navn: string; slags: string }[];
  medieListe: { id: string; titel: string; slags: string; kunstner: string; datering: string }[];
  godsListe: { id: string; navn: string; slags: string; ownerCount: number }[];
  vaabenListe: { id: string; blasonering: string; note: string }[];
};
