// Delt type-grænse for @daa/core: PRÆCIS de typer som de delte data-moduler
// (relationship, collapseSameAs, sammeSomPreflight, buildGeo, geoSelectors, buildModel)
// importerer fra deres types.ts — plus disses transitive afhængigheder, så filen
// kompilerer selvstændigt. App-specifikke typer (Aux, Raw-rækker kun loaderne bruger,
// media-typer m.m.) bliver i web/mobile's egne types.ts.
// Person-id er bigint i basen → konverteres ALTID til streng internt (README §8).
import type { GenCoord, ParentsUnknown } from './generations';

export type RawExtId = {
  person_id: number | string;
  source_id: number | string;
  linje: string | null;
  nr: number | null;
  // Generations-koordinater (Task B2 Step 1) — pulled forward for B1's rene helpers.
  slaegtled_lokal?: number | null;
  slaegtled_gennem?: number | null;
  kuld?: string | null;
};
export type RawLineage = {
  source_id: number | string;
  kode: string | null;
  navn: string | null;
  // Forgrenings-id'er (Task B2 Step 1) — pulled forward for B1's rene helpers.
  id?: string | number;
  parent_lineage_id?: string | number | null;
};
export type SlaegtRef = { id: string; navn: string; slug: string };
export type LineageRef = {
  id: string;
  slaegtId: string;
  canonicalLabel: string;
  parentLineageId: string | null;
};
export type LineageSchemeEntryRef = {
  id: string;
  schemeId: string;
  code: string;
  label: string;
};
export type RawEstate = {
  id: number | string;
  navn: string | null;
  slags: string | null;
  sted_id?: number | string | null; // → place(id); base for gods-kortmarkør
};
// Sted med koordinater. lat/lon udfyldes af berigelses-passet (tng_places + geokodning) —
// indtil da filtrerer buildGeo koordinatløse steder fra.
export type RawPlace = {
  id: number | string;
  navn: string | null;
  lat: number | null;
  lon: number | null;
};
// Geografisk-bærende fakta (fødsel/dåb/død/begravelse/bisættelse på person; vielse på family).
// fact har ingen dato-kolonne (datoer bor i evidenslaget) → år udledes af personens born/died.
export type RawFact = {
  subjekt_type: string;
  subjekt_id: number | string;
  faktatype: string | null;
  sted_id: number | string | null;
};

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

// samme_som-collapse (frontend identitets-projektion). Kanterne er retningsbestemte
// (subjekt=alias, objekt=kanonisk); afklarede identiteter foldes, konflikter karantæneres.
// Se docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md.
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

// Kanonisk Model = SUPERSET: kernen (persons/byId/indexes) som begge apps sætter,
// plus valgfrie lag som kun web udfylder i dag (lineage, sourcesBy, canonicalIdById,
// geo, genCoordsByPerson, parentsUnknownByPerson). Mobil tolererer de ekstra
// valgfrie felter uden at sætte dem — additivt sikkert.
export type Model = {
  persons: ModelPerson[];
  byId: Record<string, ModelPerson>;
  indexes: ModelIndexes;
  // Lineage (grene I–V) — valgfrit: udfyldes af loadModel når person_external_id/lineage
  // er tilgængelige; undefined = graceful degradation (ingen linje-chips/badge).
  lineage?: Lineage;
  // "Kilde i Aarbogen"-referencer pr. person (§ + trykt værk + "Linje X, nr. N"). Valgfrit.
  sourcesBy?: Record<string, SourceRef[]>;
  // samme_som-collapse: ethvert medlems-id → kanonisk id. Bor på modellen (én kilde), så
  // runtime-læsere resolver alias-id'er uden at tråde et separat map ved siden af.
  canonicalIdById?: Record<string, string>;
  // Geo-lag (kortpunkter). Valgfrit: udfyldes af loadModel; tomt indtil koordinat-berigelsen kører.
  geo?: Geo;
  // Generations-koordinater pr. kanonisk person-id (slægtled_lokal/gennem + kuld pr. linje).
  // Valgfrit: udfyldes af loadModel via buildGenCoords (Task B2); bruges af tree-byggeren (C1).
  genCoordsByPerson?: Record<string, GenCoord[]>;
  // Marker-gatet "forældre ukendt": kanonisk person-id → grad + proveniens. KUN personer hvor
  // KILDEN faktisk angiver at forbindelsen opad ikke er kendt (redaktionel markering, faktatype
  // 'forældre_ukendt' + afklaret konklusion) — IKKE personer hvor en kant bare mangler i basen.
  // Driver den ærlige inline kandidat-visning (unknownParentRing). Se docs/reviews/25-*.
  parentsUnknownByPerson?: Record<string, ParentsUnknown>;
};

// --- Geo-lag (kort) ---------------------------------------------------------
// Ét generisk kortpunkt. `kind` er "location-tag"-udvidelsespunktet: nye typer
// (kirke, slagmark, …) tilføjes her uden at røre kort-fladerne. Se buildGeo.ts.
export type GeoKind = 'estate' | 'fødsel' | 'dåb' | 'død' | 'begravelse' | 'bisættelse' | 'vielse';

export type GeoPoint = {
  placeId: string;
  navn: string; // stednavn (place.navn)
  lat: number;
  lon: number;
  kind: GeoKind;
  personId: string | null; // kanonisk person-id (fødsel/dåb/død/begravelse/bisættelse); null for gods/vielse
  estateId: string | null; // sat når kind === 'estate'
  unionId: string | null; // union-id ('f' + family_id, jf. buildModel.unionById) når kind === 'vielse'
  year: number | null; // udledt af person.born/died for fødsel/død; ellers null
};

export type Geo = {
  points: GeoPoint[]; // alle punkter (til overbliks-kort + nærhed)
  byPerson: Record<string, GeoPoint[]>; // kanonisk person-id → punkter i personens liv (inkl. ægteskab) → livskort
  byEstate: Record<string, GeoPoint>; // estate-id → godsets punkt → godskort/godsdetalje
};

// Linje-projektion pr. slægt (grene). byPerson: person_id → linje-koder; list: chips-data
// (kode, antal, stamfader=headId, fuldt navn); navn: kode → fuldt navn.
export type Lineage = {
  byPerson: Record<string, string[]>; // flere linjer pr. person (en collapsed grundlægger hører til flere)
  list: LinjeEntry[];
  navn: Record<string, string>;
};

// Delte reference-typer (bruges af Model.sourcesBy/Lineage — og af appernes Aux).
export type SourceRef = { ref: string; work: string };
export type LinjeEntry = { linje: string; count: number; headId: string | null; navn: string | null };
