// Minimal, selvstændig testdatasæt til e2e-røgtesten (task 11). Stort nok til at
// buildFeedOrder producerer et rigt sæt kort (portrætter, citater, gods, forbundet, våben)
// uden at afhænge af en levende database. Feltnavne matcher PRÆCIS det web/src/data/model.ts,
// public.ts og feedAux.ts selecter — se de respektive filer for den autoritative kilde.
const LONG_BIO_1 =
  'Han blev født på slægtens gamle gods og voksede op midt i egnens landbrug og skovbrug. Senere i livet virkede han som embedsmand ved hoffet og deltog i flere af tidens vigtige forhandlinger.';
const LONG_BIO_2 =
  'Hun overtog godset efter sin fars død og drev det gennem en urolig periode med krig og misvækst. Hendes indsats for slægtens økonomi huskes stadig i egnens lokalhistorie.';

export const PERSONS = Array.from({ length: 8 }, (_, i) => ({
  id: i + 1,
  visning_navn: `Person ${i + 1}`,
  visning_fuldt_navn: `Person ${i + 1} af Testslægten`,
  visning_foedt: String(1700 + i * 10),
  visning_doed: String(1760 + i * 10),
  visning_titel: i % 3 === 0 ? 'greve' : '',
  koen: i % 2 === 0 ? 'mand' : 'kvinde',
  privat: false,
}));

export const FAMILY_MEMBERS = [
  { family_id: 1, person_id: 1, rolle: 'partner', ordinal: 1, konfidens: 'sikker' },
  { family_id: 1, person_id: 2, rolle: 'partner', ordinal: 1, konfidens: 'sikker' },
];

export const SOURCES = [
  { id: 1, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog', udgave: 'DAA 2012-14', aar: 2012, ekstern: null },
];

export const NARRATIVES = PERSONS.map((p, i) => ({
  id: i + 1,
  subjekt_id: p.id,
  subjekt_type: 'person',
  tekst: i % 2 === 0 ? LONG_BIO_1 : LONG_BIO_2,
  privat: false,
  source_id: 1,
}));

export const ESTATES = [
  { id: 1, navn: 'Christianssæde', slags: 'Grevskab', sted_id: null },
  { id: 2, navn: 'Bukkehave', slags: 'Gods', sted_id: null },
];

export const ARMS = [
  { id: 1, blasonering: 'Delt skjold, øverst tre stjerner, nederst en løve', note: '' },
];

// PostgREST-tabelnavn → fixture-rækker. Alle andre tabeller (fx lineage, person_external_id,
// relation, conclusion, fact, media, media_variant) besvares tolerant med en tom liste — hele
// vejen igennem den rigtige kode er disse enten .catch()-hærdede eller degraderer gracefully
// til en tom liste/tomt map, matcher den etablerede "aldrig et brud på siden"-invariant.
export const TABLE_FIXTURES: Record<string, unknown[]> = {
  person: PERSONS,
  family_member: FAMILY_MEMBERS,
  narrative: NARRATIVES,
  source: SOURCES,
  estate: ESTATES,
  coat_of_arms: ARMS,
};
